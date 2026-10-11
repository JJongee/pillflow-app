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

import calendar
import datetime as dt
import json
import re
from collections import Counter

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

# 주의 항목 뷰가 있는 DB인지 (예전 백업에는 없다)
CAUTION_READY_SQL = text(
    "SELECT to_regclass('public.v_app_pregnancy_warnings') IS NOT NULL, "
    "to_regclass('public.v_app_dose_warnings') IS NOT NULL, "
    "to_regclass('public.v_app_elderly_warnings') IS NOT NULL, "
    "to_regclass('public.v_app_duplicate_warnings') IS NOT NULL, "
    "to_regclass('public.v_app_duration_warnings') IS NOT NULL"
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
           v.form_name,
           p.raw_record->>'INGR_NAME' AS ingredient_name, p.raw_record->>'NOTIFICATION_DATE' AS notification_date
    FROM v_app_dose_warnings v
    LEFT JOIN dur_dose_products p ON p.record_hash = v.record_hash
    WHERE v.item_seq IN :seqs
    """
).bindparams(bindparam("seqs", expanding=True))

# 노인주의·효능군중복주의·투여기간주의 (김서현 10/6 전달). 뷰에 성분명·공고일이 바로 들어 있다.
ELDERLY_SQL = text(
    """
    SELECT item_seq, ingredient_name, prohibition_reason, remark, notification_date, form_name,
           elderly_link_status AS status, linked_rules
    FROM v_app_elderly_warnings WHERE item_seq IN :seqs
    """
).bindparams(bindparam("seqs", expanding=True))

DUPLICATE_SQL = text(
    """
    SELECT item_seq, ingredient_name, prohibition_reason, remark, notification_date,
           duplicate_link_status AS status, linked_rules, effect_name, series_name
    FROM v_app_duplicate_warnings WHERE item_seq IN :seqs
    """
).bindparams(bindparam("seqs", expanding=True))

DURATION_SQL = text(
    """
    SELECT item_seq, ingredient_name, prohibition_reason, remark, notification_date, form_name,
           duration_link_status AS status, linked_rules
    FROM v_app_duration_warnings WHERE item_seq IN :seqs
    """
).bindparams(bindparam("seqs", expanding=True))

STATUS = {"linked": "CONFIRMED", "pending": "PENDING", "conflict": "CONFLICT"}
NOTE_ELDERLY = "고령이면 용량·부작용에 더 주의해야 해요. 의사·약사와 상담하세요."
# 노인주의는 DUR 원본부터 주의 내용이 비어 있다 (김서현 10/9 확인, 앱 대상 521건 전부).
# 빈 값을 '주의사항 없음'으로 보여 주면 안 되므로, 없다는 사실을 그대로 알려 준다.
NOTE_NO_DETAIL = "원본에 상세 주의내용이 제공되지 않았어요."
# 한 약에 같은 종류의 기준이 여러 개 오는 경우 (손채은 10/11 검수: 사노바겔에 4g·20g·2g 세 가지)
# 원본이 성분의 제형·농도별 기준을 모두 담고 있어서다. 어느 것이 이 약에 맞는지 서버가 고르지 않는다.
NOTE_MULTI = "같은 성분의 제형·농도별 참고정보예요. 이 약에 적용되는 기준으로 확정된 것은 아니에요."

# 판정 결과(applies)는 데이터 연결 상태(status)와 다른 값이다. (손채은 10/11)
#   YES     해당됨        조건이 맞고 기준도 확인된 경우
#   CHECK   확인 필요     조건은 맞지만 기준이 미확정이거나 추가 조건이 필요한 경우
#   NO      해당 안 됨     조건이 맞지 않는 경우
#   UNKNOWN 입력 없음      판단에 필요한 입력(임신 여부·복용 시작일)이 없는 경우
# 임신 주수처럼 추가 조건이 필요한 문구가 있으면 임신 여부만으로 금기라고 확정하지 않는다.
PREGNANCY_PERIOD = r"말기|초기|중기|개월|주째|주 이내|분만|수유|임신 후기|임신 전기"
NOTE_PREG_APPLIES = "임신 중이라고 하셨어요. 이 약은 임부금기로 등록돼 있으니 의사·약사와 상담하세요."
NOTE_PREG_PERIOD = "임신 시기에 따라 다를 수 있어요. 임신 여부만으로 금기라고 보지 않으니 의사·약사와 확인하세요."
NOTE_PREG_PENDING_APPLY = "임신 중이라고 하셨는데, 이 약의 임부금기 기준은 아직 확인 중이에요. 의사·약사와 상담하세요."
NOTE_PREG_NOT = "임신 중이 아니라고 하셨어요. 그래도 참고로 보여 드려요."
NOTE_PREG_UNKNOWN = "임신 여부를 입력하면 해당되는지 알려 드릴 수 있어요."
NOTE_PREG_MALE = "남성으로 입력해서 해당되지 않아요. 그래도 참고로 보여 드려요."
NOTE_DURATION_OVER = "복용한 기간이 {days}일로 기준({limit}일)을 넘었어요. 의사·약사와 상담하세요."
# 종료일이 없으면 아직 먹는 중인지 알 수 없다. 기간이 길어도 확정하지 않는다. (손채은 10/11)
NOTE_DURATION_MAYBE = ("시작일부터 오늘까지 {days}일이고 기준은 {limit}일이에요. "
                       "복용을 이미 멈췄다면 해당되지 않을 수 있어요. 종료일을 입력하거나 의사·약사와 확인해 주세요.")
NOTE_DURATION_WITHIN = "복용한 기간은 {days}일로 기준({limit}일) 안이에요."
NOTE_DURATION_CHECK = "기간 기준이 숫자로 확정되지 않아 비교하지 못했어요. 원문을 확인해 주세요."
NOTE_DURATION_UNKNOWN = "복용 시작일을 입력하면 기간을 비교해 드릴 수 있어요."
NOTE_ELDERLY_PENDING = "노인주의 기준을 확인 중이에요. 고령이라면 의사·약사와 상담하세요."
NOTE_DUPLICATE = "같은 효능군의 약을 함께 먹고 있지 않은지 의사·약사와 확인하세요."
NOTE_DUPLICATE_PENDING = "효능군 기준을 확인 중이에요. 비슷한 약을 함께 먹고 있다면 의사·약사와 상담하세요."
NOTE_DURATION = "정해진 기간을 넘겨 복용하지 말고, 더 오래 먹어야 하면 의사·약사와 상담하세요."
NOTE_DURATION_PENDING = "최대 투여기간 기준을 확인 중이에요. 오래 복용 중이라면 의사·약사와 상담하세요."
NOTE_DURATION_CONDITIONAL = "쓰는 경우에 따라 기간이 달라요. 용법 원문을 확인하세요."
NOTE_PREG_PENDING = "임부금기 등급 기준을 확인 중이에요. 임신 중이거나 가능성이 있다면 의사·약사와 상담하세요."
NOTE_PREG_CONFLICT = "임부금기 기준이 서로 달라 등급을 정하지 못했어요. 임신 중이거나 가능성이 있다면 의사·약사와 상담하세요."
NOTE_DOSE_PENDING = "1일 최대 투여량 기준을 확인 중이에요. 정해진 용량을 넘기지 말고, 궁금하면 의사·약사와 상담하세요."
# 임부금기·투여기간은 10/11부터 applies로 판정한다. 다만 금기 판정(verdict)에는 여전히 넣지 않는다.
NOTE_CAUTIONS = ("임부금기·용량주의·노인주의·효능군중복주의·투여기간주의는 cautions에 참고 정보로 알려 줘요. "
                 "금기 판정(verdict)에는 넣지 않아요.")
NOTE_DUPLICATE_SCOPE = "효능군은 약마다 따로 알려 줘요. 효능군이 같다고 바로 중복은 아니어서, 함께 먹어도 되는지는 따로 확인해야 해요."

UNITS = ("year", "month", "week")
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
    info: dict[str, str]  # 화면에 줄로 보여 줄 항목. 원문에 없는 칸은 아예 넣지 않는다
    applies: str  # YES(해당됨) / CHECK(확인 필요) / NO(해당 안 됨) / UNKNOWN(입력 없음)
    applies_note: str | None  # 그렇게 판단한 이유
    condition_note: str | None
    notice_date: str | None


class DurCheckResult(BaseModel):
    data_version: str | None
    checked_at: str
    age_unknown: bool
    pregnancy: str  # PREGNANT / NOT_PREGNANT / UNKNOWN. 임부금기 판정에 쓴다
    sex: str  # FEMALE / MALE / UNKNOWN. MALE이면 임부금기는 해당 없음
    subject: str  # SELF / OTHER / UNKNOWN. 이 프로필이 누구 약인지
    drugs: list[DurDrug]
    findings: list[DurFinding]
    cautions: list[DurCaution]
    notes: list[str]


def unique_seqs(values):
    """공백 정리 + 중복 제거 (넣은 순서 유지)."""
    return list(dict.fromkeys(v.strip() for v in values if v and v.strip()))


def add_period(date, count, unit):
    """날짜에 N년·N개월·N주를 더한다. 2월 29일처럼 같은 날이 없으면 그달의 마지막 날로 맞춘다."""
    if unit == "week":
        return date + dt.timedelta(weeks=count)
    if unit == "month":
        total = date.month - 1 + count
        year, month = date.year + total // 12, total % 12 + 1
    else:  # year
        year, month = date.year + count, date.month
    return dt.date(year, month, min(date.day, calendar.monthrange(year, month)[1]))


def age_match(birth_year, operator, value, unit, today, birth_date=None):
    """나이가 연령 기준에 해당하는지 본다. 날수 어림이 아니라 달력으로 계산한다.
    'DEFINITE'(확실히 해당) / 'POSSIBLE'(생일에 따라 해당) / None(해당 안 됨)
    생년월일을 알면 POSSIBLE이 나오지 않는다."""
    if unit not in UNITS or operator not in ("lt", "le", "gt", "ge"):
        return None
    # 'N세 이하'는 'N+1세 미만', 'N세 초과'는 'N+1세 이상'과 같다
    if operator == "le":
        operator, value = "lt", value + 1
    elif operator == "gt":
        operator, value = "ge", value + 1
    if birth_date is not None:
        earliest = latest = birth_date
    else:  # 태어난 해만 알면 1월 1일생~12월 31일생 사이
        earliest, latest = dt.date(birth_year, 1, 1), dt.date(birth_year, 12, 31)
    oldest_reached = today >= add_period(earliest, value, unit)  # 가장 나이 많은 경우
    youngest_reached = today >= add_period(latest, value, unit)  # 가장 나이 적은 경우
    if operator == "ge":
        if youngest_reached:
            return "DEFINITE"
        return "POSSIBLE" if oldest_reached else None
    if not oldest_reached:  # lt: 아직 그 나이가 안 됐으면 해당
        return "DEFINITE"
    return "POSSIBLE" if not youngest_reached else None


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


def info_of(**pairs):
    """화면에 줄로 보여 줄 항목. 원문에 값이 없는 칸은 넣지 않는다 (빈 줄로 보이지 않게)."""
    return {label: clean(value) for label, value in pairs.items() if clean(value)}


def as_rules(value):
    """linked_rules(jsonb)를 목록으로. 비었으면 빈 목록."""
    if isinstance(value, str):
        value = json.loads(value) if value.strip() else []
    return list(value or [])


def simple_caution(kind, row, rule, order, period=None, today=None):
    """노인주의·효능군중복주의·투여기간주의 한 건을 만든다. 세 뷰의 칸 구성이 같아서 함께 처리한다.
    김서현 명세: 주의 내용이 NULL이어도 경고를 빼거나 안전으로 표시하지 않는다.
    기준이 여러 개면 하나를 고르지 않고 각각 돌려준다."""
    s = row["item_seq"]
    status = STATUS.get(row["status"], "PENDING")
    rule = rule or {}
    ingr = clean(rule.get("ingredient_name")) or clean(row["ingredient_name"])
    reason = tidy_reason(rule.get("prohibition_reason")) or tidy_reason(row["prohibition_reason"])
    extra = [rule.get("remark"), row["remark"]]

    form = clean(rule.get("form_name")) or clean(row["form_name"]) if "form_name" in row else None
    if kind == "ELDERLY":
        head = "노인주의"
        advice = NOTE_ELDERLY if status == "CONFIRMED" else NOTE_ELDERLY_PENDING
        if ingr:
            head += f" · {ingr}"
        # 노인주의 원문에는 주의 내용·비고가 비어 있다 (김서현 DB 521건 전부). 없는 칸은 넣지 않는다.
        info = info_of(**{"성분": ingr, "제형": form, "주의 내용": reason})
        if not reason:
            extra.insert(0, NOTE_NO_DETAIL)
    elif kind == "DUPLICATE":
        effect = clean(rule.get("effect_name")) or clean(row["effect_name"])
        series = clean(rule.get("series_name")) or clean(row["series_name"])
        head = "효능군 중복주의" + (f" · {effect}" if effect else "")
        advice = NOTE_DUPLICATE if status == "CONFIRMED" else NOTE_DUPLICATE_PENDING
        info = info_of(**{"효능군": effect, "계열": series, "성분": ingr, "주의 내용": reason})
    else:  # DURATION
        raw = clean(rule.get("max_duration_raw"))
        head = f"최대 투여기간 {raw}" if raw else "투여기간주의"
        advice = NOTE_DURATION if status == "CONFIRMED" else NOTE_DURATION_PENDING
        if rule.get("duration_parse_status") == "conditional_or_unparsed":
            extra.insert(0, NOTE_DURATION_CONDITIONAL)
        if ingr:
            head += f" ({ingr})"
        info = info_of(**{"기간 기준": raw, "성분": ingr, "제형": form, "주의 내용": reason})
    if status != "CONFIRMED":
        head += " · 기준 확인 중"
    elif reason:
        head += f" · {reason}"

    if kind == "DURATION":
        applies, applies_note = judge_duration(status, [rule] if rule else [], period, today)
    else:  # 노인주의·효능군중복주의는 판정 기준이 없어 항상 확인 필요
        applies, applies_note = "CHECK", None
    notice = rule.get("notification_date") or row["notification_date"]
    return (order, kind, s, ingr or "", head), {
        "type": kind, "item_seqs": [s], "ingredients": [ingr] if ingr else [],
        "status": status, "grade": None, "detail": head, "info": info,
        "applies": applies, "applies_note": applies_note,
        "condition_note": join_text(*extra, advice),
        "notice_date": norm_date(str(notice)) if notice else None,
    }


def judge_pregnancy(status, reason, pregnancy, sex="UNKNOWN"):
    """임신 여부로 임부금기가 해당되는지 본다. (applies, 안내)
    성별이 남성이면 임신 여부를 묻지 않고 해당 없음으로 본다. (고연수 10/11)"""
    if sex == "MALE":
        return "NO", NOTE_PREG_MALE
    if pregnancy not in ("PREGNANT", "NOT_PREGNANT"):
        return "UNKNOWN", NOTE_PREG_UNKNOWN
    if pregnancy == "NOT_PREGNANT":
        return "NO", NOTE_PREG_NOT
    if status != "CONFIRMED":
        return "CHECK", NOTE_PREG_PENDING_APPLY
    if reason and re.search(PREGNANCY_PERIOD, reason):
        return "CHECK", NOTE_PREG_PERIOD  # 임신 시기 조건이 붙어 있으면 확정하지 않는다
    return "YES", NOTE_PREG_APPLIES


def taken_days(period, today):
    """복용한 날이 며칠인지. 시작일이 없거나 아직 시작 전이면 None."""
    started, ended = (period or (None, None))
    if started is None or started > today:
        return None
    last = min(ended, today) if ended else today
    return (last - started).days + 1


def judge_duration(status, rules, period, today):
    """복용 기간과 DUR 투여기간 기준을 비교한다. (applies, 안내)
    시작일이 없거나 기준이 숫자로 확정되지 않았으면 판정하지 않는다.
    종료일이 없으면 지금도 먹는 중인지 알 수 없어서, 기간이 길어도 확정하지 않는다."""
    days = taken_days(period, today)
    if days is None:
        return "UNKNOWN", NOTE_DURATION_UNKNOWN
    limits = [r.get("max_duration_days") for r in rules
              if r.get("duration_parse_status") == "simple_days" and r.get("max_duration_days")]
    if status != "CONFIRMED" or not limits:
        return "CHECK", NOTE_DURATION_CHECK
    limit = min(int(x) for x in limits)  # 기준이 여러 개면 짧은 쪽으로 본다
    if days <= limit:
        return "NO", NOTE_DURATION_WITHIN.format(days=days, limit=limit)
    if (period or (None, None))[1] is None:  # 종료일을 모른다
        return "CHECK", NOTE_DURATION_MAYBE.format(days=days, limit=limit)
    return "YES", NOTE_DURATION_OVER.format(days=days, limit=limit)


def build_cautions(seqs, preg=(), dose=(), elderly=(), duplicate=(), duration=(),
                   pregnancy="UNKNOWN", sex="UNKNOWN", periods=None, today=None):
    """임부금기·용량주의·노인주의·효능군중복주의·투여기간주의 참고 정보.
    판정(verdict)에는 쓰지 않고, 기준 확인 중(pending)인 기록도 빼지 않는다.
    pregnancy(임신 여부)와 periods(약별 복용 시작일·종료일)가 있으면 applies에 판정 결과를 담는다."""
    items = {}
    order = {s: i for i, s in enumerate(seqs)}
    periods = periods or {}
    today = today or dt.date.today()

    for row in preg:
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
        applies, applies_note = judge_pregnancy(status, reason, pregnancy, sex)
        key = (order.get(s, 999), "1", s, ingr or "", detail)
        items.setdefault(key, {
            "type": "PREGNANCY", "item_seqs": [s], "ingredients": [ingr] if ingr else [],
            "status": status, "grade": grade, "detail": detail, "condition_note": note,
            "applies": applies, "applies_note": applies_note,
            "info": info_of(**{"등급": grade, "성분": ingr, "금기 사유": reason}),
            "notice_date": norm_date(row["notification_date"]),
        })

    for row in dose:
        s = row["item_seq"]
        status = STATUS.get(row["status"], "PENDING")
        rules = as_rules(row["linked_rules"])
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
                    "applies": "CHECK", "applies_note": None,
                    "info": info_of(**{"성분": ingr, "1일 최대량": qty, "제형": rule.get("form_name")}),
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
                "applies": "CHECK", "applies_note": None,
                "info": info_of(**{"성분": ingr, "제형": row["form_name"], "주의 내용": reason}),
                "condition_note": join_text(row["remark"], NOTE_DOSE_PENDING),
                "notice_date": norm_date(row["notification_date"]),
            })

    for kind, rows in (("ELDERLY", elderly), ("DUPLICATE", duplicate), ("DURATION", duration)):
        for row in rows:
            rules = as_rules(row["linked_rules"]) if STATUS.get(row["status"]) == "CONFIRMED" else []
            for rule in rules or [None]:
                key, item = simple_caution(kind, row, rule, order.get(row["item_seq"], 999),
                                           periods.get(row["item_seq"]), today)
                items.setdefault(key, item)

    result = [items[k] for k in sorted(items)]
    # 한 약에 같은 종류가 여러 건이면, 어느 기준이 맞는지 확정된 게 아니라고 알려 준다
    counts = Counter((c["type"], c["item_seqs"][0]) for c in result)
    for c in result:
        if counts[(c["type"], c["item_seqs"][0])] > 1:
            c["condition_note"] = join_text(NOTE_MULTI, c["condition_note"])
    return result


def build_result(seqs, fetched, rows, age_rows=(), pending_rows=(), birth_year=None, today=None, birth_date=None):
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

    # 2) 연령금기 (태어난 해나 생년월일이 있을 때만)
    undetermined = set()
    if birth_date is not None and birth_year is None:
        birth_year = birth_date.year
    if birth_year is not None:
        for row in age_rows:
            hit = age_match(birth_year, row["age_operator"], row["age_value"], row["age_unit"], today, birth_date)
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

    # 투여기간주의 판정에 쓸 약별 복용 시작일·종료일 (내 약으로 등록한 것만 알 수 있다)
    periods = {}
    if seqs:
        rows_p = db.execute(
            select(UserDrug.item_seq, UserDrug.started_on, UserDrug.ended_on)
            .where(UserDrug.user_id == user.id, UserDrug.item_seq.in_(seqs))
        ).all()
        periods = {r[0]: (r[1], r[2]) for r in rows_p}

    fetched, rows, age_rows, pending_rows = set(), [], [], []
    age_ready = bool(db.execute(AGE_READY_SQL).scalar())
    if seqs:
        fetched = set(db.scalars(FETCHED_SQL, {"seqs": seqs}))
        if age_ready:
            age_rows = db.execute(AGE_SQL, {"seqs": seqs}).mappings().all()
            pending_rows = db.execute(AGE_PENDING_SQL, {"seqs": seqs}).mappings().all()
    caution_rows = {name: [] for name in ("preg", "dose", "elderly", "duplicate", "duration")}
    ready = dict(zip(caution_rows, db.execute(CAUTION_READY_SQL).one()))
    queries = {"preg": PREGNANCY_SQL, "dose": DOSE_SQL, "elderly": ELDERLY_SQL,
               "duplicate": DUPLICATE_SQL, "duration": DURATION_SQL}
    for name, sql in queries.items():
        if seqs and ready[name]:  # 뷰가 없는 예전 백업이면 건너뛴다
            caution_rows[name] = db.execute(sql, {"seqs": seqs}).mappings().all()
    if len(seqs) >= 2:
        rows = db.execute(PAIR_SQL, {"seqs_a": seqs, "seqs_b": seqs}).mappings().all()

    drugs, findings = build_result(seqs, fetched, rows, age_rows, pending_rows, user.birth_year,
                                   birth_date=user.birth_date)
    cautions = build_cautions(seqs, **caution_rows,
                              pregnancy=user.pregnancy or "UNKNOWN",
                              sex=user.sex or "UNKNOWN", periods=periods)

    notes = []
    if age_ready:
        notes.append("병용금기와 연령금기를 판별해요.")
        if user.birth_year is None and user.birth_date is None and (age_rows or pending_rows):
            notes.append("연령금기 기준이 있는 약이 있어요. 생년월일을 입력하면 연령금기도 확인할 수 있어요.")
        elif user.birth_date is None and any(f["type"] == "AGE" and f["condition_note"] and NOTE_BOUNDARY in f["condition_note"] for f in findings):
            notes.append("태어난 해만 알고 있어요. 생년월일을 입력하면 더 정확히 판단할 수 있어요.")
    else:
        notes.append("현재 DB에는 연령금기 데이터가 없어 병용금기만 판별해요.")
    if any(ready.values()):
        notes.append(NOTE_CAUTIONS)
    if any(c["type"] == "DUPLICATE" for c in cautions):
        notes.append(NOTE_DUPLICATE_SCOPE)
    # 실제로 비어 있는 입력만 권한다. 남성이면 임신 여부는 권하지 않는다. (고연수 10/11)
    need_preg = any(c["type"] == "PREGNANCY" and c["applies"] == "UNKNOWN" for c in cautions)
    need_period = any(c["type"] == "DURATION" and c["applies"] == "UNKNOWN" for c in cautions)
    if need_preg and need_period:
        notes.append("임신 여부나 복용 시작일을 입력하면 해당되는지까지 알려 드릴 수 있어요.")
    elif need_preg:
        notes.append("임신 여부를 입력하면 해당되는지까지 알려 드릴 수 있어요.")
    elif need_period:
        notes.append("복용 시작일을 입력하면 해당되는지까지 알려 드릴 수 있어요.")
    notes.append(NOTE_NOT_SAFE)

    version = db.execute(VERSION_SQL).scalar()
    return {
        "data_version": f"DUR API 수집 {version.astimezone().date().isoformat()}" if version else None,
        "checked_at": dt.date.today().isoformat(),
        "age_unknown": user.birth_year is None and user.birth_date is None,
        "pregnancy": user.pregnancy or "UNKNOWN",
        "sex": user.sex or "UNKNOWN",
        "subject": user.subject or "UNKNOWN",
        "drugs": drugs,
        "findings": findings,
        "cautions": cautions,
        "notes": notes,
    }
