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
# 1회 복용량 단위. 앱 입력 화면의 목록과 똑같이 6개 (고연수 10/10).
# 목록에 없는 단위는 앱이 '직접 입력'으로 dose_text에만 넣으므로, 여기서는 받지 않는다.
DoseUnit = Literal["정", "캡슐", "포", "mL", "방울", "매"]


# ---------- 복용 시간표 ----------

class ScheduleCreate(BaseModel):
    user_drug_id: int
    time: str = Field(pattern=TIME_PATTERN)
    meal_relation: MealRelation = "NONE"
    dose_text: str | None = Field(default=None, max_length=50)
    # 숫자 + 단위로 나눈 1회 복용량. 둘 다 생략할 수 있고, 서버는 기록만 하고 판정하지 않는다.
    dose_amount: float | None = Field(default=None, gt=0, le=1000)
    dose_unit: DoseUnit | None = None


class ScheduleUpdate(BaseModel):
    time: str | None = Field(default=None, pattern=TIME_PATTERN)
    meal_relation: MealRelation | None = None
    dose_text: str | None = Field(default=None, max_length=50)
    dose_amount: float | None = Field(default=None, gt=0, le=1000)
    dose_unit: DoseUnit | None = None


class ScheduleOut(BaseModel):
    id: int
    user_drug_id: int
    item_name: str | None
    time: str
    meal_relation: str
    dose_text: str | None
    dose_amount: float | None
    dose_unit: str | None


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
        "dose_amount": float(s.dose_amount) if s.dose_amount is not None else None,
        "dose_unit": s.dose_unit,
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
    # 같은 약 + 같은 시각은 한 번만. 자동 제안 화면에서 같은 항목을 두 번 저장하는 일을 막는다. (손채은 10/12)
    if db.scalar(select(Schedule).where(
            Schedule.user_id == user.id,
            Schedule.user_drug_id == ud.id,
            Schedule.time == body.time)) is not None:
        raise HTTPException(409, {"detail": "이미 같은 시각에 이 약의 시간표가 있어요.", "code": "DUPLICATE"})
    s = Schedule(
        user_id=user.id,
        user_drug_id=ud.id,
        time=body.time,
        meal_relation=body.meal_relation,
        dose_text=body.dose_text,
        dose_amount=body.dose_amount,
        dose_unit=body.dose_unit,
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
    sent = body.model_dump(exclude_unset=True)
    # 시각을 옮겨서 중복이 생기는 것도 막는다
    if sent.get("time") and sent["time"] != s.time and db.scalar(select(Schedule).where(
            Schedule.user_id == user.id,
            Schedule.user_drug_id == s.user_drug_id,
            Schedule.time == sent["time"])) is not None:
        raise HTTPException(409, {"detail": "이미 같은 시각에 이 약의 시간표가 있어요.", "code": "DUPLICATE"})
    for key, value in sent.items():
        if value is None and key not in ("dose_text", "dose_amount", "dose_unit"):
            continue  # 시간·식사 관계는 비울 수 없다. 복용량은 null로 지울 수 있다.
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


# ---------- 기간 복용 요약 (달력·이번 주 줄, 고연수 10/22 요청) ----------

MAX_SUMMARY_DAYS = 93  # 석 달치까지. 달력 한 화면이면 충분하고, 더 길면 나눠서 부른다.
DayStatus = Literal["NO_DRUG", "UPCOMING", "ALL_TAKEN", "PARTIAL", "NONE_TAKEN"]


class DaySummary(BaseModel):
    date: str
    scheduled: int   # 그날 먹기로 돼 있던 시간표 수
    taken: int
    skipped: int
    pending: int     # 기록이 없는 수
    day_status: DayStatus


def schedule_applies(s: Schedule, ud: UserDrug, day: dt.date, has_log: bool) -> bool:
    """그날 그 시간표가 '먹기로 돼 있던' 시간표인지.

    - 그날 기록(TAKEN/SKIPPED)이 있으면 무조건 포함한다.
    - 복용 시작일이 있으면 그날부터, 없으면 시간표를 만든 날부터 센다.
      → 시간표가 생기기 전 날짜는 '안 먹음'이 아니라 '약 없음'이 된다.
    - 복용 종료일이 있으면 그날까지만 센다.
    """
    if has_log:
        return True
    start = ud.started_on or (s.created_at.date() if s.created_at else None)
    if start is not None and day < start:
        return False
    if ud.ended_on is not None and day > ud.ended_on:
        return False
    return True


def day_status_of(day: dt.date, today: dt.date, scheduled: int, taken: int, skipped: int, pending: int) -> str:
    if scheduled == 0:
        return "NO_DRUG"
    if day > today:
        return "UPCOMING"
    if taken == scheduled:
        return "ALL_TAKEN"
    if taken > 0:
        return "PARTIAL"
    return "NONE_TAKEN"  # 전부 건너뜀이거나 아직 기록이 없음 (오늘이면 아직 안 먹은 것일 수 있다)


@router.get("/intakes/summary", response_model=list[DaySummary])
def intakes_summary(
    from_: dt.date = Query(..., alias="from"),
    to: dt.date = Query(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """from~to(둘 다 포함) 날짜별 복용 요약. 달력·'이번 주 복용' 줄에 쓴다.

    날짜마다 한 줄씩, 시간표가 없는 날도 NO_DRUG로 돌려준다 (앱이 빈 날을 채울 필요 없음).
    오늘은 아직 먹을 시각이 안 됐어도 pending으로 세므로, 앱은 오늘 칸을 '진행 중'으로 따로 그려도 된다.
    """
    if to < from_:
        raise HTTPException(422, "to는 from보다 빠를 수 없어요.")
    if (to - from_).days + 1 > MAX_SUMMARY_DAYS:
        raise HTTPException(422, f"한 번에 {MAX_SUMMARY_DAYS}일까지만 조회할 수 있어요.")
    rows = my_schedules(db, user)
    ids = [s.id for s, _ in rows]
    logs: dict[tuple[int, dt.date], str] = {}
    if ids:
        stmt = select(IntakeLog).where(
            IntakeLog.schedule_id.in_(ids), IntakeLog.date >= from_, IntakeLog.date <= to
        )
        logs = {(log.schedule_id, log.date): log.status for log in db.scalars(stmt)}
    today = dt.date.today()
    out = []
    day = from_
    while day <= to:
        scheduled = taken = skipped = pending = 0
        for s, ud in rows:
            status = logs.get((s.id, day))
            if not schedule_applies(s, ud, day, status is not None):
                continue
            scheduled += 1
            if status == "TAKEN":
                taken += 1
            elif status == "SKIPPED":
                skipped += 1
            else:
                pending += 1
        out.append({
            "date": day.isoformat(),
            "scheduled": scheduled, "taken": taken, "skipped": skipped, "pending": pending,
            "day_status": day_status_of(day, today, scheduled, taken, skipped, pending),
        })
        day += dt.timedelta(days=1)
    return out


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