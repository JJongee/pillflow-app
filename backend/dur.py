"""DUR 판별 API: 병용금기 + 연령금기 판정, 임부금기·용량주의 참고 정보. (김서현 DB 사용)

판정 기준 (api_contract v0.2, 김서현 ERD 명세)
- CONTRAINDICATED : 함께 고른 약 사이 병용금기 기록이 있거나, 사용자 나이가 연령금기 기준에 해당(될 수 있음)
- NO_KNOWN_ISSUE  : DUR 수집이 끝난 약인데, 이번 조합·나이에서 걸린 기록이 없음 ("안전"이 아님)
- UNDETERMINED    : DUR 수집 기록이 없는 약, 또는 연령 기준이 '확인 중'이라 판단할 수 없는 약 → 판정 불가

병용금기는 A-B, B-A 양쪽을 모두 조회하고, 순서를 바꿔 넣어도 결과가 같다.
연령금기는 태어난 해만 알기 때문에, 생일에 따라 해당 여부가 갈리는 경계도 "해당될 수 있음"으로 경고한다.
연령금기 표가 없는 예전 DB에서도 병용금기는 그대로 동작한다.

임부금기·용량주의는 사용자 입력(임신 여부, 1일 복용량)이 아직 없어서 판정(verdict)에 넣지 않고,
`cautions`에 약별 참고 정보로 돌려준다. 기준 확인 중(pending)·충돌(conflict)인 기록도 빼지 않는다.
앱은 findings의 AGE 외 type을 모두 병용금기로 보여 주므로, 이 정보는 findings가 아니라 cautions에만 넣는다.
"""

import datetime as dt
import json
import re

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

# 연령금기 표가 있는 DB인지 (예전 백업이면 없음)
AGE_READY_SQL = text("SELECT to_regclass('public.v_dur_age_verified') IS NOT NULL")

# 확인된 연령금기 규칙 (약 ↔ 규칙 연결이 검증된 것만)
AGE_SQL = text(
    """
    SELECT v.item_seq, v.dur_seq, v.ingredient_name, v.age_base, v.age_value, v.age_unit, v.age_operator,
           v.prohibition_reason, v.remark, v.product_prohibition_reason, v.product_remark,
           r.notification_date
    FROM v_dur_age_verified v
    JOIN dur_age_rules r ON r.dur_seq = v.dur_seq
    WHERE v.item_seq IN :seqs
    """
).bindparams(bindparam("seqs", expanding=True))

# 연령금기 데이터는 있지만 기준 연결을 아직 확인 중인 약
AGE_PENDING_SQL = text(
    "SELECT item_seq, prohibition_reason, remark FROM v_dur_age_pending WHERE item_seq IN :seqs"
).bindparams(bindparam("seqs", expanding=True))

# 임부금기·용량주의 뷰가 있는 DB인지
CAUTION_READY_SQL = text(
    "SELECT to_regclass('public.v_app_pregnancy_warnings') IS NOT NULL, "
    "to_regclass('public.v_app_dose_warnings') IS NOT NULL"
)

PREGNANCY_SQL = text(
    """
    SELECT v.item_seq, v.prohibition_reason, v.remark, v.grade_raw, v.grade_link_status AS status,
           p.raw_record->>'INGR_NAME' AS ingredient_name, p.raw_record->>'NOTIFICATION_DATE' AS notification_date
    FROM v_app_pregnancy_warnings v
    LEFT JOIN dur_pregnancy_products p ON p.record_hash = v.record_hash
    WHERE v.item_seq IN :seqs
    """
).bindparams(bindparam("seqs", expanding=True))

DOSE_SQL = text(
    """
    SELECT v.item_seq, v.prohibition_reason, v.remark, v.dose_link_status AS status, v.linked_rules,
           p.raw_record->>'INGR_NAME' AS ingredient_name, p.raw_record->>'NOTIFICATION_DATE' AS notification_date
    FROM v_app_dose_warnings v
    LEFT JOIN dur_dose_products p ON p.record_hash = v.record_hash
    WHERE v.item_seq IN :seqs
    """
).bindparams(bindparam("seqs", expanding=True))

STATUS = {"linked": "CONFIRMED", "pending": "PENDING", "conflict": "CONFLICT"}
NOTE_PREG_PENDING = "임부금기 등급 기준을 확인 중이에요. 임신 중이거나 가능성이 있다면 의사·약사와 상담하세요."
NOTE_PREG_CONFLICT = "임부금기 기준이 서로 달라 등급을 정하지 못했어요. 임신 중이거나 가능성이 있다면 의사·약사와 상담하세요."
NOTE_DOSE_PENDING = "1일 최대 투여량 기준을 확인 중이에요. 정해진 용량을 넘기지 말고, 궁금하면 의사·약사와 상담하세요."
NOTE_CAUTIONS = "임부금기·용량주의는 판정에 넣지 않고 cautions에 참고 정보로 알려 줘요. (임신 여부·복용량 입력 전)"

UNIT_DAYS = {"year": 365.25, "month": 30.4375, "week": 7}
RANK = {"NO_KNOWN_ISSUE": 0, "UNDETERMINED": 1, "CONTRAINDICATED": 2}
NOTE_NOT_SAFE = "기록 없음(NO_KNOWN_ISSUE)은 '안전'이 아니라, 수집된 데이터에 금기 기록이 없다는 뜻이에요."
NOTE_BOUNDARY = "태어난 해만으로 판단해서, 생일에 따라 해당되지 않을 수도 있어요."


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


class DurCaution(BaseModel):
    type: str  # PREGNANCY(임부금기) / DOSE(용량주의)
    item_seqs: list[str]  # 약 1개 (findings와 같은 모양)
    ingredients: list[str]
    status: str  # CONFIRMED / PENDING(기준 확인 중) / CONFLICT(기준 충돌)
    grade: str | None  # 임부금기 등급 (1등급·2등급), 모르면 null
    detail: str
    condition_note: str | None
    notice_date: str | None


class DurCheckResult(BaseModel):
    data_version: str | None
    checked_at: str
    age_unknown: bool
    drugs: list[DurDrug]
    findings: list[DurFinding]
    cautions: list[DurCaution]
    notes: list[str]


def unique_seqs(values):
    """공백 정리 + 중복 제거 (넣은 순서 유지)."""
    return list(dict.fromkeys(v.strip() for v in values if v and v.strip()))


def age_match(birth_year, operator, value, unit, today):
    """태어난 해로 나이 범위를 잡고 연령 기준에 해당하는지 본다.
    'DEFINITE'(확실히 해당) / 'POSSIBLE'(생일에 따라 해당) / None(해당 안 됨)"""
    if unit not in UNIT_DAYS or operator not in ("lt", "le", "gt", "ge"):
        return None
    oldest = (today - dt.date(birth_year, 1, 1)).days  # 1월 1일생이면 가장 많은 나이
    youngest = (today - dt.date(birth_year, 12, 31)).days  # 12월 31일생이면 가장 적은 나이
    # 'N세 이하'는 'N+1세 미만', 'N세 초과'는 'N+1세 이상'과 같다
    if operator == "le":
        operator, value = "lt", value + 1
    elif operator == "gt":
        operator, value = "ge", value + 1
    limit = value * UNIT_DAYS[unit]
    if operator == "lt":
        if oldest < limit:
            return "DEFINITE"
        return "POSSIBLE" if youngest < limit else None
    if youngest >= limit:
        return "DEFINITE"
    return "POSSIBLE" if oldest >= limit else None


def join_text(*parts):
    parts = [clean(p) for p in parts if clean(p)]
    return " / ".join(dict.fromkeys(parts)) or None


def tidy_reason(value):
    """DUR 원문 사유 정리: 줄바꿈·따옴표를 정리하고 '-'만 있으면 없음으로 본다."""
    value = clean(value)
    if not value:
        return None
    value = re.sub(r"\s+", " ", value).strip().strip('"').strip()
    value = value.strip("- ").strip()
    return value or None


def build_cautions(seqs, preg_rows=(), dose_rows=()):
    """임부금기·용량주의 참고 정보. 판정에는 쓰지 않는다. 기준 확인 중인 기록도 빼지 않는다."""
    items = {}
    order = {s: i for i, s in enumerate(seqs)}

    for row in preg_rows:
        s = row["item_seq"]
        status = STATUS.get(row["status"], "PENDING")
        grade = clean(row["grade_raw"]) if status == "CONFIRMED" else None
        reason = tidy_reason(row["prohibition_reason"])
        ingr = clean(row["ingredient_name"])
        if status == "CONFIRMED":
            detail = f"임부금기 {grade}" if grade else "임부금기"
            note = join_text(row["remark"], "임신 중이거나 가능성이 있다면 의사·약사와 상담하세요.")
        else:
            detail = "임부금기 기준 확인 중"
            note = join_text(row["remark"], NOTE_PREG_CONFLICT if status == "CONFLICT" else NOTE_PREG_PENDING)
        if reason:
            detail += f" · {reason}"
        key = (order.get(s, 999), "1", s, ingr or "", detail)
        items.setdefault(key, {
            "type": "PREGNANCY", "item_seqs": [s], "ingredients": [ingr] if ingr else [],
            "status": status, "grade": grade, "detail": detail, "condition_note": note,
            "notice_date": norm_date(row["notification_date"]),
        })

    for row in dose_rows:
        s = row["item_seq"]
        status = STATUS.get(row["status"], "PENDING")
        rules = row["linked_rules"] or []
        if isinstance(rules, str):
            rules = json.loads(rules)
        if status == "CONFIRMED" and rules:
            for rule in rules:
                ingr = clean(rule.get("ingredient_name")) or clean(row["ingredient_name"])
                qty = clean(rule.get("max_qty_raw"))
                detail = f"1일 최대 투여량 {qty}" if qty else "용량주의"
                note = join_text(tidy_reason(rule.get("prohibition_reason")), rule.get("remark"), row["remark"],
                                 "하루 복용량이 이 양을 넘지 않게 하세요.")
                key = (order.get(s, 999), "2", s, ingr or "", detail)
                items.setdefault(key, {
                    "type": "DOSE", "item_seqs": [s], "ingredients": [ingr] if ingr else [],
                    "status": "CONFIRMED", "grade": None, "detail": detail, "condition_note": note,
                    "notice_date": norm_date(row["notification_date"]),
                })
        else:
            ingr = clean(row["ingredient_name"])
            reason = tidy_reason(row["prohibition_reason"])
            detail = "1일 최대 투여량 기준 확인 중" + (f" · {reason}" if reason else "")
            key = (order.get(s, 999), "2", s, ingr or "", detail)
            items.setdefault(key, {
                "type": "DOSE", "item_seqs": [s], "ingredients": [ingr] if ingr else [],
                "status": "CONFLICT" if status == "CONFLICT" else "PENDING", "grade": None, "detail": detail,
                "condition_note": join_text(row["remark"], NOTE_DOSE_PENDING),
                "notice_date": norm_date(row["notification_date"]),
            })

    return [items[k] for k in sorted(items)]


def build_result(seqs, fetched, rows, age_rows=(), pending_rows=(), birth_year=None, today=None):
    """DB에서 읽은 기록으로 약별 판정과 금기 목록을 만든다. (DB 없이도 시험 가능한 순수 함수)"""
    today = today or dt.date.today()
    findings = {}

    # 1) 병용금기
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
        key = ("1", pair[0], pair[1], reason or "", note or "")
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

    # 2) 연령금기 (태어난 해가 있을 때만)
    undetermined = set()
    if birth_year is not None:
        for row in age_rows:
            hit = age_match(birth_year, row["age_operator"], row["age_value"], row["age_unit"], today)
            if hit is None:
                continue
            s, base = row["item_seq"], clean(row["age_base"])
            reason = clean(row["prohibition_reason"]) or clean(row["product_prohibition_reason"])
            note = join_text(row["remark"], row["product_remark"], NOTE_BOUNDARY if hit == "POSSIBLE" else None)
            key = ("2", s, base or "", clean(row["ingredient_name"]) or "", reason or "")
            if key not in findings:
                findings[key] = {
                    "type": "AGE",
                    "item_seqs": [s],
                    "ingredients": [x for x in [clean(row["ingredient_name"])] if x],
                    "detail": f"{base} 금기" + (f" · {reason}" if reason else ""),
                    "condition_note": note,
                    "notice_no": None,
                    "notice_date": norm_date(str(row["notification_date"])) if row["notification_date"] else None,
                }
        # 연령금기 데이터는 있는데 기준을 확인 중인 약 → 판단할 수 없음(안전 아님)
        for row in pending_rows:
            s = row["item_seq"]
            undetermined.add(s)
            key = ("3", s, clean(row["prohibition_reason"]) or "", clean(row["remark"]) or "", "")
            if key not in findings:
                findings[key] = {
                    "type": "AGE",
                    "item_seqs": [s],
                    "ingredients": [],
                    "detail": "연령금기 기준 확인 중" + (f" · {clean(row['prohibition_reason'])}" if clean(row["prohibition_reason"]) else ""),
                    "condition_note": join_text(row["remark"], "나이 기준을 확인하지 못해 판정할 수 없어요. 의사·약사와 상담하세요."),
                    "notice_no": None,
                    "notice_date": None,
                }

    finding_list = [findings[k] for k in sorted(findings)]
    contraindicated = {
        s for k, f in findings.items() if k[0] in ("1", "2") for s in f["item_seqs"]
    }

    drugs = []
    for s in seqs:
        verdict = "NO_KNOWN_ISSUE" if s in fetched else "UNDETERMINED"
        if s in undetermined and RANK["UNDETERMINED"] > RANK[verdict]:
            verdict = "UNDETERMINED"
        if s in contraindicated:
            verdict = "CONTRAINDICATED"
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

    fetched, rows, age_rows, pending_rows = set(), [], [], []
    age_ready = bool(db.execute(AGE_READY_SQL).scalar())
    if seqs:
        fetched = set(db.scalars(FETCHED_SQL, {"seqs": seqs}))
        if age_ready:
            age_rows = db.execute(AGE_SQL, {"seqs": seqs}).mappings().all()
            pending_rows = db.execute(AGE_PENDING_SQL, {"seqs": seqs}).mappings().all()
    preg_rows, dose_rows = [], []
    preg_ready, dose_ready = db.execute(CAUTION_READY_SQL).one()
    if seqs and preg_ready:
        preg_rows = db.execute(PREGNANCY_SQL, {"seqs": seqs}).mappings().all()
    if seqs and dose_ready:
        dose_rows = db.execute(DOSE_SQL, {"seqs": seqs}).mappings().all()
    if len(seqs) >= 2:
        rows = db.execute(PAIR_SQL, {"seqs_a": seqs, "seqs_b": seqs}).mappings().all()

    drugs, findings = build_result(seqs, fetched, rows, age_rows, pending_rows, user.birth_year)
    cautions = build_cautions(seqs, preg_rows, dose_rows)

    notes = []
    if age_ready:
        notes.append("병용금기와 연령금기를 판별해요.")
        if user.birth_year is None and (age_rows or pending_rows):
            notes.append("연령금기 기준이 있는 약이 있어요. 태어난 해를 입력하면 연령금기도 확인할 수 있어요.")
    else:
        notes.append("현재 DB에는 연령금기 데이터가 없어 병용금기만 판별해요.")
    if preg_ready or dose_ready:
        notes.append(NOTE_CAUTIONS)
    notes.append(NOTE_NOT_SAFE)

    version = db.execute(VERSION_SQL).scalar()
    return {
        "data_version": f"DUR API 수집 {version.astimezone().date().isoformat()}" if version else None,
        "checked_at": dt.date.today().isoformat(),
        "age_unknown": user.birth_year is None,
        "drugs": drugs,
        "findings": findings,
        "cautions": cautions,
        "notes": notes,
    }
