from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import text
from starlette.exceptions import HTTPException as StarletteHTTPException

import models  # noqa: F401  (표 정의를 불러오는 용도)
from auth import create_user
from auth import router as auth_router
from db import Base, SessionLocal, engine
from drugs import router as drugs_router
from dur import router as dur_router
from me import router as me_router
from schedules import router as schedules_router
from suggest import router as suggest_router

app = FastAPI(title="Pillflow API")

# 계약서 공통 규칙: 에러는 {"detail": 사람이 읽을 메시지, "code": 기계가 읽을 값}
ERROR_CODES = {
    400: "BAD_REQUEST",
    401: "UNAUTHORIZED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    409: "DUPLICATE",
}


@app.exception_handler(StarletteHTTPException)
async def http_error(request: Request, exc: StarletteHTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "code": ERROR_CODES.get(exc.status_code, "ERROR")},
        headers=getattr(exc, "headers", None),
    )


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={"detail": jsonable_encoder(exc.errors()), "code": "VALIDATION_ERROR"},
    )


app.include_router(drugs_router)
app.include_router(auth_router)
app.include_router(me_router)
app.include_router(schedules_router)
app.include_router(suggest_router)
app.include_router(dur_router)

# 서버용 표(users, user_drugs, schedules, intake_logs)가 없으면 만들고,
# 데모 계정(앱 목업과 같은 값)을 준비한다. 김서현 님 표는 건드리지 않는다.
Base.metadata.create_all(engine)
# 예전에 만들어진 users 표에는 birth_date 칸이 없다. create_all은 칸을 더해 주지 않으므로 직접 더한다.
with engine.begin() as _conn:
    _conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS birth_date DATE"))
    _conn.execute(text("ALTER TABLE schedules ADD COLUMN IF NOT EXISTS dose_amount NUMERIC(10,3)"))
    _conn.execute(text("ALTER TABLE schedules ADD COLUMN IF NOT EXISTS dose_unit VARCHAR(10)"))
    _conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS pregnancy VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN'"))
    # 먼저 만들어진 서버에서는 이 칸이 VARCHAR(10)이라 NOT_PREGNANT(12글자)가 안 들어간다
    _conn.execute(text("ALTER TABLE users ALTER COLUMN pregnancy TYPE VARCHAR(20)"))
    _conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS subject VARCHAR(10) NOT NULL DEFAULT 'UNKNOWN'"))
    _conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS sex VARCHAR(10) NOT NULL DEFAULT 'UNKNOWN'"))
    _conn.execute(text("ALTER TABLE user_drugs ADD COLUMN IF NOT EXISTS started_on DATE"))
    _conn.execute(text("ALTER TABLE user_drugs ADD COLUMN IF NOT EXISTS ended_on DATE"))
    # 예전 시간표는 만든 시각을 모르므로 이 칸을 더한 시점(지금)으로 채워진다
    _conn.execute(text("ALTER TABLE schedules ADD COLUMN IF NOT EXISTS created_at TIMESTAMP NOT NULL DEFAULT now()"))
    # 직접 추가 항목(10/23): item_seq 없이 이름만으로 등록한다
    _conn.execute(text("ALTER TABLE user_drugs ALTER COLUMN item_seq DROP NOT NULL"))
    _conn.execute(text("ALTER TABLE user_drugs ADD COLUMN IF NOT EXISTS custom_name VARCHAR(100)"))
    _conn.execute(text("ALTER TABLE user_drugs ADD COLUMN IF NOT EXISTS kind VARCHAR(12)"))
with SessionLocal() as _db:
    create_user(_db, "demo@pillflow.app", "1234")


@app.get("/")
def hello():
    return {"message": "pillflow server"}
