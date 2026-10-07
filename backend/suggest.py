"""자동 복용 시간표 제안 API. (준비안 "자동 시간표 준비안 (필플로우 2단계)"의 규칙 9개)

서버는 시간을 **제안만** 한다. 저장은 사용자가 확인한 뒤 앱이 기존 POST /me/schedules로 한다.
그래서 지금 시간표·복용 기록 API는 하나도 바뀌지 않는다.

하지 않는 것 (안전 원칙)
- 용량(몇 정, 몇 mL)은 고르지 않는다. 나이별 용량이 절반 가까이라 잘못 고를 위험이 크다.
- 병용금기는 시간을 나눠서 해결하지 않는다. 경고와 상담 안내만 붙인다. (제안서 5.5)
- 용법 문장을 읽지 못한 약은 짐작하지 않고 "직접 입력"으로 돌려준다.
"""

import datetime as dt
import re

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from auth import get_current_user
from db import get_db
from drugs import DRUG_BY_SEQ, clean
from models import User, UserDrug
from schedules import TIME_PATTERN, item_name_of

router = APIRouter(prefix="/api/v1/me", tags=["schedules"])

# 기준 시각 5개. 사용자가 요청에서 바꿀 수 있다.
BASE_TIMES = {"wake": "07:00", "breakfast": "08:00", "lunch": "12:30", "dinner": "18:30", "bedtime": "22:30"}

# 횟수 → 어떤 기준 시각에 둘지 (준비안 규칙 4)
SLOT_PLAN = {
    1: ["breakfast"],
    2: ["breakfast", "dinner"],
    3: ["breakfast", "lunch", "dinner"],
    4: ["breakfast", "lunch", "dinner", "bedtime"],
}
MEAL_SLOTS = {"breakfast", "lunch", "dinner"}  # 식사 관계로 시각을 옮길 수 있는 칸

# 먹는 약이 아닌 단서 (규칙 1)
NOT_ORAL = r"바르|붙이|부착|점안|점이|점비|안약|눈에|좌제|삽입|주입|흡입|주사|도포|뿌리|분무|패치|씌우|가글|양치|헹구|관장|환부|질에|항문|피부에|두피"
ORAL = r"복용|먹|마시|삼키|물과 함께|씹어|식후|식전"

# 식사 관계 단서 (규칙 5). 앞에 올수록 우선.
MEAL_CUES = [
    ("EMPTY", r"공복|식간|식사와 식사"),
    ("BEFORE", r"식전|식사\s*전|식사하기\s*전"),
    ("AFTER", r"식후|식사\s*후|식사하신?\s*후"),
]
NEGATE = r"(?:피하|피해|말|금)"  # "공복 시를 피하여" 처럼 뒤집는 문구 (규칙 6)

AS_NEEDED = r"필요시|필요할\s*때|필요에\s*따라"
# 나이에 따라 용법이 달라지는 문장 (손채은 10/7 제안). 서버는 나이에 맞는 용량을 고르지 않는다.
AGE_NUMBER = r"만?\s*(\d+)\s*(?:세|개월)"
AGE_GROUP = r"소아|영아|유아|고령자|노인"
AGE_MIN = r"만?\s*(\d+)\s*세\s*이상"
NOTE_AGE_UNKNOWN = "나이에 따라 먹는 양이 달라요. 생년월일을 입력하면 더 정확히 안내할 수 있어요."
NOTE_AGE_CHECK = "나이에 따라 먹는 양이 달라요. 본인 나이에 맞는 내용인지 용법 원문을 확인해 주세요."
BEDTIME_CUE = r"취침|자기\s*전|잠자기\s*전|잘\s*때"

SHIFT = {"BEFORE": -30, "AFTER": 30, "EMPTY": 120, "NONE": 0}  # 분

NOTE_SUGGEST_ONLY = "제안일 뿐이에요. 의사·약사가 정해 준 복용법이 있으면 그것을 따르세요."
NOTE_NO_DOSE = "몇 정·몇 mL를 먹을지는 제안하지 않아요. 용법 원문을 확인하세요."


class SuggestRequest(BaseModel):
    user_drug_ids: list[int] | None = Field(default=None, min_length=1, max_length=50)
    base_times: dict[str, str] | None = None

    @field_validator("base_times")
    @classmethod
    def check_base_times(cls, value):
        if value is None:
            return None
        for key, time_value in value.items():
            if key not in BASE_TIMES:
                raise ValueError(f"기준 시각 이름이 잘못됐어요: {key}")
            if not re.fullmatch(TIME_PATTERN, time_value):
                raise ValueError(f"시각은 HH:mm 형식이어야 해요: {time_value}")
        return value


class SuggestSlot(BaseModel):
    time: str
    meal_relation: str


class DrugSuggestion(BaseModel):
    user_drug_id: int
    item_seq: str
    item_name: str
    confidence: str  # HIGH(그대로 쓸 만함) / CONFIRM(확인 필요) / NONE(제안 없음)
    times_per_day: int | None
    slots: list[SuggestSlot]
    basis: str | None  # 근거가 된 용법 문장 조각
    warnings: list[str]


class SuggestResult(BaseModel):
    suggestions: list[DrugSuggestion]
    base_times: dict[str, str]
    age_known: bool  # 나이를 알면 나이별 용법에 맞춰 확인을 요청한다
    dur_findings: list[dict]
    notes: list[str]


def shift_time(hhmm, minutes):
    """"08:00"을 분 단위로 옮긴다. 자정을 넘기면 00:00~23:59 안으로 돌린다."""
    hour, minute = (int(x) for x in hhmm.split(":"))
    total = (hour * 60 + minute + minutes) % (24 * 60)
    return f"{total // 60:02d}:{total % 60:02d}"


def to_minutes(hhmm):
    hour, minute = (int(x) for x in hhmm.split(":"))
    return hour * 60 + minute


def find_sentence(text_value, pattern):
    """규칙에 걸린 부분이 들어 있는 문장 하나를 근거로 돌려준다."""
    for part in re.split(r"(?<=[.!?。])\s+|\n+", text_value):
        if re.search(pattern, part):
            return re.sub(r"\s+", " ", part).strip()[:200]
    return re.sub(r"\s+", " ", text_value).strip()[:200]


def is_oral(text_value):
    """먹는 약인지. 먹는 단서가 있으면 먹는 약으로 보고, 없이 외용 단서만 있으면 아니다."""
    if re.search(ORAL, text_value):
        return True
    return not re.search(NOT_ORAL, text_value)


def read_times_per_day(text_value):
    """하루 몇 번인지 읽는다. (횟수, 범위인지) 또는 (None, False)."""
    unit = r"(?:회|번)"
    span = re.search(rf"(?:1일|하루|일)\s*(\d+)\s*[~\-∼]\s*(\d+)\s*{unit}", text_value)
    if span:
        low, high = int(span.group(1)), int(span.group(2))
        if 1 <= low <= high:
            return low, True  # 범위면 작은 값으로 제안 (규칙 3)
    one = re.search(rf"(?:1일|하루)\s*(\d+)\s*{unit}", text_value)
    if one and int(one.group(1)) >= 1:
        return int(one.group(1)), False
    return None, False


def read_meal_relation(text_value):
    """식사 관계를 읽는다. "피하여"가 붙은 단서는 쓰지 않는다. (규칙 5, 6)"""
    for relation, pattern in MEAL_CUES:
        for match in re.finditer(pattern, text_value):
            tail = text_value[match.end():match.end() + 12]
            if re.search(NEGATE, tail):
                # "공복 시를 피하여" → 공복을 쓰지 말고, 대신 식후로 둔다
                if relation == "EMPTY":
                    return "AFTER", "공복을 피하라고 적혀 있어 식후로 제안했어요."
                continue
            return relation, None
    return "NONE", None


def read_min_gap_hours(text_value):
    """"4시간 이상" 같은 최소 복용 간격. (규칙 7)
    "4~6시간 마다"처럼 범위면 작은 값(4시간)이 최소 간격이다."""
    match = re.search(r"(\d+)\s*(?:[~\-∼]\s*\d+\s*)?시간\s*(?:이상|마다|간격)", text_value)
    return int(match.group(1)) if match else None


def read_age_limits(text_value):
    """용법에 적힌 '만 N세 이상' 기준들. 없으면 빈 목록."""
    return sorted({int(m) for m in re.findall(AGE_MIN, text_value)})


def age_warning(text_value, age_range):
    """나이와 용법이 맞지 않으면 확인을 요청한다. (손채은 10/7 제안)
    age_range는 (가장 적은 나이, 가장 많은 나이). 모르면 None.
    나이 구분이 없거나, 나이를 알고 그 구간에 들어가면 경고하지 않는다."""
    ages = sorted({int(m) for m in re.findall(AGE_NUMBER, text_value)})
    group = bool(re.search(AGE_GROUP, text_value))
    if not ages and not group:
        return None
    if age_range is None:
        return NOTE_AGE_UNKNOWN
    limits = read_age_limits(text_value)
    # 적힌 기준 중 가장 낮은 나이에도 못 미치면, 그 용법은 이 사람 것이 아니다
    if limits and age_range[1] < limits[0]:
        return f"이 약의 용법은 만 {limits[0]}세 이상 기준이에요. 나이에 맞는 용법인지 의사·약사와 확인해 주세요."
    # 나이 구간이 둘 이상이면 어느 구간인지 사람이 골라야 한다
    if len(ages) >= 2 or group:
        return NOTE_AGE_CHECK
    return None


def suggest_one(use_method, base_times, age_range=None):
    """용법 문장 하나를 읽어 제안을 만든다. (DB·FastAPI 없이 시험 가능한 순수 함수)
    age_range를 주면 나이별 용법이 있는 약에 확인 요청을 붙인다."""
    none_result = {"confidence": "NONE", "times_per_day": None, "slots": [], "basis": None, "warnings": []}
    text_value = clean(use_method)
    if text_value is None:
        return {**none_result, "warnings": ["용법 정보가 없어요. 복용 시간을 직접 정해 주세요."]}

    basis = re.sub(r"\s+", " ", text_value).strip()[:200]
    if not is_oral(text_value):  # 규칙 1
        return {**none_result, "basis": find_sentence(text_value, NOT_ORAL),
                "warnings": ["먹는 약이 아니어서 복용 시간을 제안하지 않아요."]}

    count, is_range = read_times_per_day(text_value)  # 규칙 3
    if count is None:
        if re.search(AS_NEEDED, text_value):  # 규칙 2
            return {**none_result, "basis": find_sentence(text_value, AS_NEEDED),
                    "warnings": ["필요할 때만 먹는 약이라 고정 시간을 두지 않아요."]}
        return {**none_result, "basis": basis,
                "warnings": ["용법 문장에서 하루 복용 횟수를 찾지 못했어요. 직접 정해 주세요."]}
    if count not in SLOT_PLAN:  # 규칙 4: 5회 이상은 직접 입력
        return {**none_result, "times_per_day": count, "basis": find_sentence(text_value, r"\d+\s*(?:회|번)"),
                "warnings": [f"하루 {count}회는 자동으로 배치하지 않아요. 직접 정해 주세요."]}

    warnings = []
    if is_range:
        warnings.append(f"횟수가 범위로 적혀 있어 작은 값({count}회)으로 제안했어요. 확인해 주세요.")

    note = age_warning(text_value, age_range)  # 나이별 용법 확인 (손채은 10/7)
    if note:
        warnings.append(note)

    relation, note = read_meal_relation(text_value)  # 규칙 5, 6
    if note:
        warnings.append(note)

    plan = list(SLOT_PLAN[count])
    # "취침 전"이 있으면 마지막 회를 취침으로 바꾼다 (규칙 5)
    if re.search(BEDTIME_CUE, text_value) and plan[-1] != "bedtime":
        plan[-1] = "bedtime"
    # 1일 1회 공복이면 기상 직후로 (준비안 시간대 정의)
    if count == 1 and relation == "EMPTY":
        plan = ["wake"]

    slots = []
    for slot in plan:
        if slot in MEAL_SLOTS:
            slots.append({"time": shift_time(base_times[slot], SHIFT[relation]), "meal_relation": relation})
        else:
            # 기상·취침은 식사 시각이 아니라 그대로 둔다
            slots.append({"time": base_times[slot], "meal_relation": "NONE"})
    slots.sort(key=lambda s: to_minutes(s["time"]))

    gap = read_min_gap_hours(text_value)  # 규칙 7
    if gap and len(slots) >= 2:
        shortest = min(
            to_minutes(b["time"]) - to_minutes(a["time"]) for a, b in zip(slots, slots[1:])
        )
        if shortest < gap * 60:
            warnings.append(f"{gap}시간 이상 띄우라고 적혀 있는데 제안한 시간 간격이 더 좁아요. 시간을 조정해 주세요.")

    return {
        "confidence": "CONFIRM" if (is_range or warnings) else "HIGH",
        "times_per_day": count,
        "slots": slots,
        "basis": find_sentence(text_value, r"\d+\s*(?:회|번)"),
        "warnings": warnings,
    }


def years_since(born, today):
    """만 나이. 생일이 안 지났으면 한 살 적다."""
    years = today.year - born.year
    return years - ((today.month, today.day) < (born.month, born.day))


def user_age_range(user):
    """오늘 기준 만 나이를 (가장 적은 나이, 가장 많은 나이)로. 생년월일을 알면 두 값이 같다."""
    if user.birth_date is None and user.birth_year is None:
        return None
    today = dt.date.today()
    if user.birth_date is not None:
        earliest = latest = user.birth_date
    else:  # 태어난 해만 알면 1월 1일생~12월 31일생 사이
        earliest, latest = dt.date(user.birth_year, 1, 1), dt.date(user.birth_year, 12, 31)
    return years_since(latest, today), years_since(earliest, today)


@router.post("/schedules/suggest", response_model=SuggestResult)
def suggest_schedules(
    body: SuggestRequest | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """내 약의 용법 문장을 읽어 복용 시각을 제안한다. 저장은 하지 않는다.
    user_drug_ids를 빼면 내 약 전체, base_times를 빼면 기본 시각을 쓴다."""
    base_times = {**BASE_TIMES, **((body.base_times if body else None) or {})}
    age_range = user_age_range(user)

    stmt = select(UserDrug).where(UserDrug.user_id == user.id).order_by(UserDrug.id)
    if body is not None and body.user_drug_ids is not None:
        # 남의 약 번호가 섞여 있어도 내 것만 남는다 (존재 자체를 알리지 않음)
        stmt = stmt.where(UserDrug.id.in_(body.user_drug_ids))
    my_drugs = list(db.scalars(stmt))

    suggestions = []
    for ud in my_drugs:
        drug = DRUG_BY_SEQ.get(ud.item_seq) or {}
        result = suggest_one(drug.get("use_method"), base_times, age_range)
        suggestions.append({
            "user_drug_id": ud.id,
            "item_seq": ud.item_seq,
            # 앱은 이름을 항상 글자로 받으므로 목록에 없는 약도 채워 준다
            "item_name": item_name_of(ud) or f"등록되지 않은 약 ({ud.item_seq})",
            **result,
        })

    # 병용금기는 시간을 나눠 해결하지 않고 경고만 붙인다 (규칙 8)
    dur_findings = []
    seqs = [ud.item_seq for ud in my_drugs]
    if len(seqs) >= 2:
        from dur import PAIR_SQL, build_result
        rows = db.execute(PAIR_SQL, {"seqs_a": seqs, "seqs_b": seqs}).mappings().all()
        _, dur_findings = build_result(seqs, set(seqs), rows)

    notes = [NOTE_SUGGEST_ONLY, NOTE_NO_DOSE]
    if dur_findings:
        notes.append("병용금기가 있는 약이 있어요. 시간을 나눠도 해결되지 않으니 의사·약사와 상담하세요.")
    return {
        "suggestions": suggestions,
        "base_times": base_times,
        "age_known": age_range is not None,
        "dur_findings": dur_findings,
        "notes": notes,
    }
