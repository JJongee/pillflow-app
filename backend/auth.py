import os
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pwdlib import PasswordHash
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from db import get_db
from models import User

# 개발용 비밀키. 실제 배포 전에는 환경변수 SECRET_KEY로 바꿔야 한다.
SECRET_KEY = os.environ.get("SECRET_KEY", "pillflow-dev-secret-key-change-me-0123456789")
ALGORITHM = "HS256"
TOKEN_HOURS = 24

password_hash = PasswordHash.recommended()
bearer = HTTPBearer(auto_error=False)


def normalize_email(email):
    return email.strip().lower()


def create_user(db: Session, email, password):
    """가입시킨다. 이미 있는 이메일이면 None."""
    email = normalize_email(email)
    if db.scalar(select(User).where(User.email == email)):
        return None
    user = User(email=email, password_hash=password_hash.hash(password))
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return None
    db.refresh(user)
    return user


class SignupRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: str = Field(min_length=4, max_length=128)


class LoginRequest(BaseModel):
    email: str
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
):
    """다른 API에서 '로그인한 사용자'를 알아내는 데 쓴다."""
    if credentials is None:
        raise HTTPException(status_code=401, detail="로그인이 필요해요.")
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        user = db.get(User, int(payload.get("sub")))
    except (jwt.InvalidTokenError, TypeError, ValueError):
        raise HTTPException(status_code=401, detail="로그인이 만료됐어요.")
    if user is None:
        raise HTTPException(status_code=401, detail="로그인이 만료됐어요.")
    return user


router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/signup", response_model=UserOut, status_code=201)
def signup(body: SignupRequest, db: Session = Depends(get_db)):
    user = create_user(db, body.email, body.password)
    if user is None:
        raise HTTPException(status_code=409, detail="이미 가입된 이메일이에요.")
    return user


@router.post("/login", response_model=TokenOut)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == normalize_email(body.email)))
    if user is None or not password_hash.verify(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호를 확인해 주세요.")
    expire = datetime.now(timezone.utc) + timedelta(hours=TOKEN_HOURS)
    token = jwt.encode({"sub": str(user.id), "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)
    return {"access_token": token, "token_type": "bearer"}


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    """토큰이 제대로 동작하는지 확인용."""
    return user