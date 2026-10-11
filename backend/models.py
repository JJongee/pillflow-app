import datetime as dt

from sqlalchemy import Date, ForeignKey, Numeric, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    birth_year: Mapped[int | None] = mapped_column(default=None)
    # 생년월일을 알면 연령금기를 정확히 판단한다. 모르면 birth_year로 범위를 잡는다.
    birth_date: Mapped[dt.date | None] = mapped_column(Date, default=None)
    # 임신 여부. 민감한 정보라 선택 입력이고, 안 고르면 'UNKNOWN'으로 둔다. (손채은 10/11)
    # NOT_PREGNANT가 12글자라 넉넉히 잡는다
    pregnancy: Mapped[str] = mapped_column(String(20), default="UNKNOWN", server_default="UNKNOWN")
    # 이 프로필이 누구 것인지. 가족 약을 대신 관리하는 경우가 있어 '약 먹는 사람' 기준으로 둔다. (고연수 10/11)
    subject: Mapped[str] = mapped_column(String(10), default="UNKNOWN", server_default="UNKNOWN")
    # 성별. 남성이면 임부금기는 해당되지 않는다고 판정한다.
    sex: Mapped[str] = mapped_column(String(10), default="UNKNOWN", server_default="UNKNOWN")
    created_at: Mapped[dt.datetime] = mapped_column(server_default=func.now())


class UserDrug(Base):
    __tablename__ = "user_drugs"
    __table_args__ = (UniqueConstraint("user_id", "item_seq"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    item_seq: Mapped[str] = mapped_column(String(30))
    memo: Mapped[str | None] = mapped_column(String(200), default=None)
    # 복용 시작일·종료일. 투여기간주의를 보려면 시작일이 있어야 한다. 둘 다 선택 입력.
    started_on: Mapped[dt.date | None] = mapped_column(Date, default=None)
    ended_on: Mapped[dt.date | None] = mapped_column(Date, default=None)
    created_at: Mapped[dt.datetime] = mapped_column(server_default=func.now())


class Schedule(Base):
    """사용자가 직접 정한 복용 시간. 약을 지우면 같이 지워진다."""

    __tablename__ = "schedules"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    user_drug_id: Mapped[int] = mapped_column(ForeignKey("user_drugs.id", ondelete="CASCADE"))
    time: Mapped[str] = mapped_column(String(5))  # "08:30"
    meal_relation: Mapped[str] = mapped_column(String(10), default="NONE")
    dose_text: Mapped[str | None] = mapped_column(String(50), default=None)
    # 1회 복용량을 숫자와 단위로 나눠 둔다. 자동 용량 판정은 아직 하지 않고 기록만 한다.
    dose_amount: Mapped[float | None] = mapped_column(Numeric(10, 3), default=None)
    dose_unit: Mapped[str | None] = mapped_column(String(10), default=None)


class IntakeLog(Base):
    """그날 그 시간표를 먹었는지(TAKEN) 건너뛰었는지(SKIPPED). 기록이 없으면 PENDING."""

    __tablename__ = "intake_logs"
    __table_args__ = (UniqueConstraint("schedule_id", "date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    schedule_id: Mapped[int] = mapped_column(ForeignKey("schedules.id", ondelete="CASCADE"))
    date: Mapped[dt.date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(10))
    recorded_at: Mapped[dt.datetime] = mapped_column(server_default=func.now())