import datetime as dt
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from auth import get_current_user
from db import get_db
from me import drug_lookup, get_own_drug
from models import IntakeLog, Schedule, User, UserDrug

router = APIRouter(prefix="/api/v1/me", tags=["schedules"])

TIME_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"  # 00:00 ~ 23:59
MealRelation = Literal["BEFORE", "AFTER", "EMPTY", "NONE"]
IntakeStatus = Literal["TAKEN", "SKIPPED", "PENDING"]


# ---------- 복용 시간표 ----------

class ScheduleCreate(BaseModel):
    user_drug_id: int
    time: str = Field(pattern=TIME_PATTERN)
    meal_relation: MealRelation = "NONE"
    dose_text: str | None = Field(default=None, max_length=50)


class ScheduleUpdate(BaseModel):
    time: str | None = Field(default=None, pattern=TIME_PATTERN)
    meal_relation: MealRelation | None = None
    dose_text: str | None = Field(default=None, max_length=50)


class ScheduleOut(BaseModel):
    id: int
    user_drug_id: int
    item_name: str | None
    time: str
    meal_relation: str
    dose_text: str | None


def item_name_of(ud: UserDrug):
    return (drug_lookup().get(ud.item_seq) or {}).get("item_name")


def schedule_out(s: Schedule, ud: UserDrug):
    return {
        "id": s.id,
        "user_drug_id": s.user_drug_id,
        "item_name": item_name_of(ud),
        "time": s.time,
        "meal_relation": s.meal_relation,
        "dose_text": s.dose_text,
    }


def my_schedules(db: Session, user: User):
    """내 시간표 전체를 (시간표, 약) 쌍으로, 시간 순서대로."""
    stmt = (
        select(Schedule, UserDrug)
        .join(UserDrug, Schedule.user_drug_id == UserDrug.id)
        .where(Schedule.user_id == user.id)
        .order_by(Schedule.time, Schedule.id)
    )
    return db.execute(stmt).all()


def get_own_schedule(db: Session, user: User, schedule_id: int):
    """내 시간표만 찾는다. 남의 것이거나 없으면 404."""
    stmt = (
        select(Schedule, UserDrug)
        .join(UserDrug, Schedule.user_drug_id == UserDrug.id)
        .where(Schedule.id == schedule_id, Schedule.user_id == user.id)
    )
    row = db.execute(stmt).first()
    if row is None:
        raise HTTPException(status_code=404, detail="시간표를 찾을 수 없어요.")
    return row


@router.get("/schedules", response_model=list[ScheduleOut])
def list_schedules(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return [schedule_out(s, ud) for s, ud in my_schedules(db, user)]


@router.post("/schedules", response_model=ScheduleOut, status_code=201)
def add_schedule(
    body: ScheduleCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ud = get_own_drug(db, user, body.user_drug_id)  # 내 약이 아니면 404
    s = Schedule(
        user_id=user.id,
        user_drug_id=ud.id,
        time=body.time,
        meal_relation=body.meal_relation,
        dose_text=body.dose_text,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return schedule_out(s, ud)


@router.patch("/schedules/{schedule_id}", response_model=ScheduleOut)
def update_schedule(
    schedule_id: int,
    body: ScheduleUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    s, ud = get_own_schedule(db, user, schedule_id)
    for key, value in body.model_dump(exclude_unset=True).items():
        if value is None and key != "dose_text":
            continue  # 시간·식사 관계는 비울 수 없다
        setattr(s, key, value)
    db.commit()
    db.refresh(s)
    return schedule_out(s, ud)


@router.delete("/schedules/{schedule_id}", status_code=204)
def delete_schedule(
    schedule_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    s, _ = get_own_schedule(db, user, schedule_id)
    db.delete(s)
    db.commit()
    return Response(status_code=204)


# ---------- 복용 기록 ----------

class IntakeUpsert(BaseModel):
    schedule_id: int
    date: dt.date
    status: IntakeStatus


class IntakeOut(BaseModel):
    schedule_id: int
    date: str
    time: str
    item_name: str | None
    status: str
    recorded_at: str | None


def intake_out(s: Schedule, ud: UserDrug, day: dt.date, log: IntakeLog | None):
    return {
        "schedule_id": s.id,
        "date": day.isoformat(),
        "time": s.time,
        "item_name": item_name_of(ud),
        "status": log.status if log else "PENDING",
        "recorded_at": log.recorded_at.isoformat(timespec="seconds") if log else None,
    }


@router.get("/intakes", response_model=list[IntakeOut])
def list_intakes(
    date: dt.date = Query(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """그날 시간표 전체 + 기록 상태. 기록이 없으면 PENDING."""
    rows = my_schedules(db, user)
    ids = [s.id for s, _ in rows]
    logs = {}
    if ids:
        stmt = select(IntakeLog).where(IntakeLog.date == date, IntakeLog.schedule_id.in_(ids))
        logs = {log.schedule_id: log for log in db.scalars(stmt)}
    return [intake_out(s, ud, date, logs.get(s.id)) for s, ud in rows]


@router.put("/intakes", response_model=IntakeOut)
def put_intake(
    body: IntakeUpsert,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """같은 시간표·날짜면 덮어쓴다. PENDING으로 보내면 기록을 지운다."""
    s, ud = get_own_schedule(db, user, body.schedule_id)
    log = db.scalar(
        select(IntakeLog).where(IntakeLog.schedule_id == s.id, IntakeLog.date == body.date)
    )
    if body.status == "PENDING":
        if log is not None:
            db.delete(log)
            db.commit()
        return intake_out(s, ud, body.date, None)
    if log is None:
        log = IntakeLog(schedule_id=s.id, date=body.date, status=body.status)
        db.add(log)
    else:
        log.status = body.status
        log.recorded_at = func.now()
    db.commit()
    db.refresh(log)
    return intake_out(s, ud, body.date, log)