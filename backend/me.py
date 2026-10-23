import datetime as dt

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from auth import get_current_user
from db import get_db
from models import User, UserDrug

router = APIRouter(prefix="/api/v1/me", tags=["me"])


# 임신 여부. 민감한 정보라 선택 입력이고, 안 고르면 UNKNOWN이다. (손채은 10/11)
Pregnancy = Literal["PREGNANT", "NOT_PREGNANT", "UNKNOWN"]
# 이 프로필이 누구 약인지. 가족 약을 대신 관리하는 경우가 있다. (고연수 10/11)
Subject = Literal["SELF", "OTHER", "UNKNOWN"]
Sex = Literal["FEMALE", "MALE", "UNKNOWN"]


# 직접 추가 항목의 종류 (고연수 10/23). 영양제·건강보조식품은 SUPPLEMENT.
Kind = Literal["SUPPLEMENT", "MEDICINE", "OTHER"]


class UserDrugCreate(BaseModel):
    """item_seq(약 목록의 약) 또는 custom_name(직접 추가) 중 하나만 보낸다."""

    item_seq: str | None = Field(default=None, min_length=1, max_length=30)
    custom_name: str | None = Field(default=None, min_length=1, max_length=100)
    kind: Kind | None = None  # 직접 추가일 때만. 안 보내면 OTHER
    memo: str | None = Field(default=None, max_length=200)
    # 복용 시작일·종료일. 투여기간주의를 보려면 시작일이 있어야 한다.
    started_on: dt.date | None = None
    ended_on: dt.date | None = None

    @field_validator("custom_name")
    @classmethod
    def strip_name(cls, value):
        if value is not None:
            value = value.strip()
            if not value:
                raise ValueError("이름을 입력해 주세요.")
        return value


class UserDrugUpdate(BaseModel):
    memo: str | None = Field(default=None, max_length=200)
    started_on: dt.date | None = None
    ended_on: dt.date | None = None
    # 직접 추가 항목만 바꿀 수 있다 (약 목록의 약은 422)
    custom_name: str | None = Field(default=None, min_length=1, max_length=100)
    kind: Kind | None = None


class UserDrugOut(BaseModel):
    id: int
    item_seq: str | None  # 직접 추가 항목은 null
    is_custom: bool
    custom_name: str | None
    kind: str | None
    item_name: str | None  # 직접 추가 항목은 custom_name이 들어간다
    entp_name: str | None
    image_url: str | None
    memo: str | None
    started_on: str | None
    ended_on: str | None
    created_at: str


def drug_lookup():
    # 서버가 켜질 때 DB(drugs 표)에서 읽어 둔 약 목록
    from drugs import DRUG_BY_SEQ

    return DRUG_BY_SEQ


def is_custom(ud: UserDrug) -> bool:
    return ud.item_seq is None


def to_out(ud: UserDrug):
    d = (drug_lookup().get(ud.item_seq) or {}) if ud.item_seq else {}
    return {
        "id": ud.id,
        "item_seq": ud.item_seq,
        "is_custom": is_custom(ud),
        "custom_name": ud.custom_name,
        "kind": ud.kind,
        "item_name": ud.custom_name if is_custom(ud) else d.get("item_name"),
        "entp_name": d.get("entp_name"),
        "image_url": d.get("image_url"),
        "memo": ud.memo,
        "started_on": ud.started_on.isoformat() if ud.started_on else None,
        "ended_on": ud.ended_on.isoformat() if ud.ended_on else None,
        "created_at": ud.created_at.date().isoformat(),
    }


def get_own_drug(db: Session, user: User, drug_id: int):
    """내 약만 찾는다. 남의 약이거나 없으면 404."""
    ud = db.scalar(select(UserDrug).where(UserDrug.id == drug_id, UserDrug.user_id == user.id))
    if ud is None:
        raise HTTPException(status_code=404, detail="등록된 약을 찾을 수 없어요.")
    return ud


@router.get("/drugs", response_model=list[UserDrugOut])
def list_my_drugs(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(UserDrug).where(UserDrug.user_id == user.id).order_by(UserDrug.id))
    return [to_out(ud) for ud in rows]


@router.post("/drugs", response_model=UserDrugOut, status_code=201)
def add_my_drug(
    body: UserDrugCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if (body.item_seq is None) == (body.custom_name is None):
        raise HTTPException(status_code=422, detail="item_seq(약 목록의 약) 또는 custom_name(직접 추가) 중 하나만 보내 주세요.")
    if body.started_on and body.ended_on and body.ended_on < body.started_on:
        raise HTTPException(status_code=422, detail="복용 종료일이 시작일보다 빠를 수 없어요.")
    if body.custom_name is not None:
        # 직접 추가: 같은 이름(대소문자·공백 무시)이 이미 있으면 409
        exists = db.scalar(
            select(UserDrug).where(UserDrug.user_id == user.id, UserDrug.item_seq.is_(None),
                                   func.lower(UserDrug.custom_name) == body.custom_name.lower())
        )
        if exists:
            raise HTTPException(status_code=409, detail="이미 같은 이름으로 추가한 항목이 있어요.")
        ud = UserDrug(user_id=user.id, item_seq=None, custom_name=body.custom_name,
                      kind=body.kind or "OTHER", memo=body.memo,
                      started_on=body.started_on, ended_on=body.ended_on)
        db.add(ud)
        db.commit()
        db.refresh(ud)
        return to_out(ud)
    if body.item_seq not in drug_lookup():
        raise HTTPException(status_code=404, detail="약을 찾을 수 없어요.")
    exists = db.scalar(
        select(UserDrug).where(UserDrug.user_id == user.id, UserDrug.item_seq == body.item_seq)
    )
    if exists:
        raise HTTPException(status_code=409, detail="이미 등록한 약이에요.")
    ud = UserDrug(user_id=user.id, item_seq=body.item_seq, memo=body.memo,
                  started_on=body.started_on, ended_on=body.ended_on)
    db.add(ud)
    db.commit()
    db.refresh(ud)
    return to_out(ud)


@router.patch("/drugs/{drug_id}", response_model=UserDrugOut)
def update_my_drug(
    drug_id: int,
    body: UserDrugUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ud = get_own_drug(db, user, drug_id)
    sent = body.model_dump(exclude_unset=True)
    if ("custom_name" in sent or "kind" in sent) and not is_custom(ud):
        raise HTTPException(status_code=422, detail="약 목록에서 고른 약은 이름과 종류를 바꿀 수 없어요.")
    if is_custom(ud) and (sent.get("custom_name", "x") is None or sent.get("kind", "x") is None):
        raise HTTPException(status_code=422, detail="직접 추가한 항목의 이름과 종류는 비울 수 없어요.")
    if "custom_name" in sent:
        sent["custom_name"] = sent["custom_name"].strip()
        if not sent["custom_name"]:
            raise HTTPException(status_code=422, detail="이름을 입력해 주세요.")
    for key, value in sent.items():
        setattr(ud, key, value)  # 보낸 칸만 바뀌고, null로 지울 수 있다
    if ud.started_on and ud.ended_on and ud.ended_on < ud.started_on:
        raise HTTPException(status_code=422, detail="복용 종료일이 시작일보다 빠를 수 없어요.")
    db.commit()
    db.refresh(ud)
    return to_out(ud)


@router.delete("/drugs/{drug_id}", status_code=204)
def delete_my_drug(
    drug_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ud = get_own_drug(db, user, drug_id)
    db.delete(ud)
    db.commit()
    return Response(status_code=204)


# ---------- 프로필 (연령금기 판별용) ----------

class Profile(BaseModel):
    """birth_date(생년월일)를 넣으면 연령금기를 정확히 판단한다.
    birth_year(태어난 해)만 넣으면 생일에 따라 갈리는 경우를 '해당될 수 있음'으로 경고한다."""

    birth_year: int | None = Field(default=None, ge=1900, le=2100)
    birth_date: dt.date | None = None
    pregnancy: Pregnancy = "UNKNOWN"
    subject: Subject = "UNKNOWN"
    sex: Sex = "UNKNOWN"

    @field_validator("birth_date")
    @classmethod
    def check_birth_date(cls, value):
        if value is not None and not (dt.date(1900, 1, 1) <= value <= dt.date.today()):
            raise ValueError("생년월일은 1900-01-01부터 오늘까지여야 해요.")
        return value


def profile_out(user: User):
    return {
        "birth_year": user.birth_year,
        "birth_date": user.birth_date.isoformat() if user.birth_date else None,
        "pregnancy": user.pregnancy or "UNKNOWN",
        "subject": user.subject or "UNKNOWN",
        "sex": user.sex or "UNKNOWN",
    }


@router.get("/profile", response_model=Profile)
def get_profile(user: User = Depends(get_current_user)):
    return profile_out(user)


@router.put("/profile", response_model=Profile)
def put_profile(
    body: Profile,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """보낸 칸만 바뀐다. 생년월일을 넣으면 태어난 해도 같이 맞춘다."""
    sent = body.model_dump(exclude_unset=True)
    if "birth_date" in sent:
        user.birth_date = body.birth_date
        if body.birth_date is not None:
            user.birth_year = body.birth_date.year
    if "pregnancy" in sent:
        user.pregnancy = body.pregnancy
    if "subject" in sent:
        user.subject = body.subject
    if "sex" in sent:
        user.sex = body.sex
    if "birth_year" in sent:
        user.birth_year = body.birth_year
        # 해를 바꿨는데 저장된 생년월일과 어긋나면, 오래된 생년월일을 지운다
        if user.birth_date is not None and user.birth_date.year != body.birth_year:
            user.birth_date = None
    db.commit()
    return profile_out(user)
