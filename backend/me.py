import datetime as dt

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from auth import get_current_user
from db import get_db
from models import User, UserDrug

router = APIRouter(prefix="/api/v1/me", tags=["me"])


class UserDrugCreate(BaseModel):
    item_seq: str = Field(min_length=1, max_length=30)
    memo: str | None = Field(default=None, max_length=200)


class UserDrugUpdate(BaseModel):
    memo: str | None = Field(default=None, max_length=200)


class UserDrugOut(BaseModel):
    id: int
    item_seq: str
    item_name: str | None
    entp_name: str | None
    image_url: str | None
    memo: str | None
    created_at: str


def drug_lookup():
    # 서버가 켜질 때 DB(drugs 표)에서 읽어 둔 약 목록
    from drugs import DRUG_BY_SEQ

    return DRUG_BY_SEQ


def to_out(ud: UserDrug):
    d = drug_lookup().get(ud.item_seq) or {}
    return {
        "id": ud.id,
        "item_seq": ud.item_seq,
        "item_name": d.get("item_name"),
        "entp_name": d.get("entp_name"),
        "image_url": d.get("image_url"),
        "memo": ud.memo,
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
    if body.item_seq not in drug_lookup():
        raise HTTPException(status_code=404, detail="약을 찾을 수 없어요.")
    exists = db.scalar(
        select(UserDrug).where(UserDrug.user_id == user.id, UserDrug.item_seq == body.item_seq)
    )
    if exists:
        raise HTTPException(status_code=409, detail="이미 등록한 약이에요.")
    ud = UserDrug(user_id=user.id, item_seq=body.item_seq, memo=body.memo)
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
    ud.memo = body.memo
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
    if "birth_year" in sent:
        user.birth_year = body.birth_year
        # 해를 바꿨는데 저장된 생년월일과 어긋나면, 오래된 생년월일을 지운다
        if user.birth_date is not None and user.birth_date.year != body.birth_year:
            user.birth_date = None
    db.commit()
    return profile_out(user)
