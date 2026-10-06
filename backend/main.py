from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
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
with SessionLocal() as _db:
    create_user(_db, "demo@pillflow.app", "1234")


@app.get("/")
def hello():
    return {"message": "pillflow server"}
