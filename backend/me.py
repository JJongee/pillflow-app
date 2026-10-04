from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
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
    birth_year: int | None = Field(default=None, ge=1900, le=2100)


@router.get("/profile", response_model=Profile)
def get_profile(user: User = Depends(get_current_user)):
    return {"birth_year": user.birth_year}


@router.put("/profile", response_model=Profile)
def put_profile(
    body: Profile,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    user.birth_year = body.birth_year
    db.commit()
    return {"birth_year": user.birth_year}
