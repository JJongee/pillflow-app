"""DUR 병용금기 판별 API. (김서현 DB의 dur_interactions, dur_fetch_status 사용)

판정 기준 (api_contract v0.2, 김서현 ERD 명세)
- CONTRAINDICATED : 함께 고른 약 중 병용금기 기록이 있는 약
- NO_KNOWN_ISSUE  : DUR 수집이 끝난 약인데, 이번 조합에서 걸린 기록이 없음 ("안전"이 아님)
- UNDETERMINED    : DUR 수집 기록이 없는 약 → 판정 불가
병용금기는 A-B, B-A 양쪽을 모두 조회하고, 순서를 바꿔 넣어도 결과가 같다.
"""

import datetime as dt

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import bindparam, select, text
from sqlalchemy.orm import Session

from auth import get_current_user
from db import get_db
from drugs import DRUG_BY_SEQ, clean, norm_date
from models import User, UserDrug

router = APIRouter(prefix="/api/v1/dur", tags=["dur"])

# 고른 약끼리의 병용금기 기록 (A-B, B-A 모두 걸린다)
PAIR_SQL = text(
    """
    SELECT item_seq_a, item_seq_b, prohibition_reason, notification_date, raw_record
    FROM dur_interactions
    WHERE item_seq_a IN :seqs_a AND item_seq_b IN :seqs_b
    """
).bindparams(bindparam("seqs_a", expanding=True), bindparam("seqs_b", expanding=True))

# DUR 수집이 끝난 약 (0건도 '수집 완료'로 기록돼 있음)
FETCHED_SQL = text(
    "SELECT item_seq FROM dur_fetch_status WHERE item_seq IN :seqs"
).bindparams(bindparam("seqs", expanding=True))

VERSION_SQL = text("SELECT MAX(fetched_at) FROM dur_fetch_status")

NOTES = [
    "현재는 병용금기만 판별해요. 연령금기 등은 아직 데이터가 없어요.",
    "기록 없음(NO_KNOWN_ISSUE)은 '안전'이 아니라, 수집된 데이터에 금기 기록이 없다는 뜻이에요.",
]


class DurCheckRequest(BaseModel):
    item_seqs: list[str] | None = Field(default=None, min_length=1, max_length=50)


class DurDrug(BaseModel):
    item_seq: str
    item_name: str
    verdict: str


class DurFinding(BaseModel):
    type: str
    item_seqs: list[str]
    ingredients: list[str]
    detail: str
    condition_note: str | None
    notice_no: str | None
    notice_date: str | None


class DurCheckResult(BaseModel):
    data_version: str | None
    checked_at: str
    age_unknown: bool
    drugs: list[DurDrug]
    findings: list[DurFinding]
    notes: list[str]


def unique_seqs(values):
    """공백 정리 + 중복 제거 (넣은 순서 유지)."""
    return list(dict.fromkeys(v.strip() for v in values if v and v.strip()))


def build_result(seqs, fetched, rows):
    """DB에서 읽은 기록으로 약별 판정과 금기 목록을 만든다. (DB 없이도 시험 가능한 순수 함수)"""
    findings = {}
    for row in rows:
        a, b = row["item_seq_a"], row["item_seq_b"]
        if a == b:
            continue
        raw = row["raw_record"] or {}
        ingr_a, ingr_b = clean(raw.get("INGR_KOR_NAME")), clean(raw.get("MIXTURE_INGR_KOR_NAME"))
        # 약 번호가 작은 쪽을 앞에 둬서 A-B, B-A를 같은 쌍으로 만든다
        if a <= b:
            pair, ingredients = [a, b], [ingr_a, ingr_b]
        else:
            pair, ingredients = [b, a], [ingr_b, ingr_a]
        reason = clean(row["prohibition_reason"])
        note = clean(raw.get("REMARK"))
        notice_date = norm_date(row["notification_date"])
        key = (pair[0], pair[1], reason or "", note or "", notice_date or "")
        if key not in findings:
            findings[key] = {
                "type": "COMBINATION",
                "item_seqs": pair,
                "ingredients": [x for x in ingredients if x],
                "detail": reason,
                "condition_note": note,
                "notice_no": None,  # DUR API 응답에는 고시번호가 없음
                "notice_date": notice_date,
            }
    finding_list = [findings[k] for k in sorted(findings)]

    flagged = {s for f in finding_list for s in f["item_seqs"]}
    drugs = []
    for s in seqs:
        if s in flagged:
            verdict = "CONTRAINDICATED"
        elif s in fetched:
            verdict = "NO_KNOWN_ISSUE"
        else:
            verdict = "UNDETERMINED"
        # 앱은 이름을 항상 글자로 받으므로, 목록에 없는 약도 이름을 채워 준다
        name = (DRUG_BY_SEQ.get(s) or {}).get("item_name") or f"등록되지 않은 약 ({s})"
        drugs.append({"item_seq": s, "item_name": name, "verdict": verdict})
    return drugs, finding_list


@router.post("/check", response_model=DurCheckResult)
def dur_check(
    body: DurCheckRequest | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """item_seqs를 빼고 보내면 내 약 전체로 판별한다."""
    if body is None or body.item_seqs is None:
        stmt = select(UserDrug.item_seq).where(UserDrug.user_id == user.id).order_by(UserDrug.id)
        seqs = unique_seqs(db.scalars(stmt))
    else:
        seqs = unique_seqs(body.item_seqs)

    fetched, rows = set(), []
    if seqs:
        fetched = set(db.scalars(FETCHED_SQL, {"seqs": seqs}))
    if len(seqs) >= 2:
        rows = db.execute(PAIR_SQL, {"seqs_a": seqs, "seqs_b": seqs}).mappings().all()

    drugs, findings = build_result(seqs, fetched, rows)
    version = db.execute(VERSION_SQL).scalar()
    return {
        "data_version": f"DUR API 수집 {version.astimezone().date().isoformat()}" if version else None,
        "checked_at": dt.date.today().isoformat(),
        "age_unknown": user.birth_year is None,
        "drugs": drugs,
        "findings": findings,
        "notes": NOTES,
    }
