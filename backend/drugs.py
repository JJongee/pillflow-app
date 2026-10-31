"""약 검색·상세 API. 김서현 DB의 drugs, drug_images 표에서 읽는다. (CSV는 더 이상 필요 없음)"""

import datetime as dt
import logging
import re

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.exc import ProgrammingError

from db import engine

logger = logging.getLogger("uvicorn.error")  # uvicorn 콘솔에 같이 찍힌다
LOAD_INFO = {}  # 서버가 켜질 때 읽은 약 목록 정보. GET / 에서 보여 준다

# 일반/전문 구분 칸(drugs.etc_otc)은 10/23 김서현 덤프부터 있다. 예전 덤프면 NULL로 채운다.
ETC_OTC_SQL = text(
    "SELECT 1 FROM information_schema.columns WHERE table_name = 'drugs' AND column_name = 'etc_otc'"
)
DRUG_SQL_TEMPLATE = """
    SELECT d.item_seq, d.item_name, d.entp_name,
           d.efcy_qesitm, d.use_method_qesitm, d.atpn_warn_qesitm, d.atpn_qesitm,
           d.intrc_qesitm, d.se_qesitm, d.deposit_method_qesitm,
           d.open_de, d.update_de,
           {etc_otc} AS etc_otc,
           (SELECT MIN(i.item_image) FROM drug_images i WHERE i.item_seq = d.item_seq) AS item_image
    FROM drugs d
    ORDER BY d.item_seq
    """
DRUG_SQL = text(DRUG_SQL_TEMPLATE.format(etc_otc="d.etc_otc"))
DRUG_SQL_OLD = text(DRUG_SQL_TEMPLATE.format(etc_otc="NULL"))
ETC_OTC_VALUES = ("일반의약품", "전문의약품")


def clean(value):
    """앞뒤 공백·특수 공백을 정리하고, 빈 값은 None으로 돌려준다."""
    if value is None:
        return None
    value = str(value).replace("\xa0", " ").strip()
    return value or None


def norm_date(value):
    """20210129, 2024.5.9, 2024-05-09 → 2024-05-09 형식으로 통일. 못 알아보면 None."""
    value = clean(value)
    if value is None:
        return None
    parts = re.findall(r"\d+", value)
    if len(parts) == 1 and len(parts[0]) == 8:
        y, m, d = parts[0][:4], parts[0][4:6], parts[0][6:]
    elif len(parts) == 3:
        y, m, d = parts
    else:
        return None
    try:
        return dt.date(int(y), int(m), int(d)).isoformat()
    except ValueError:
        return None


def squash(text_value):
    """띄어쓰기를 없애고 소문자로 바꾼다. (검색 비교용)"""
    return re.sub(r"\s+", "", text_value).lower()


def etc_otc_of(value):
    value = clean(value)
    return value if value in ETC_OTC_VALUES else None


def rx_required_of(value):
    value = etc_otc_of(value)
    if value is None:
        return None
    return value == "전문의약품"


def row_to_drug(row):
    drug = {
        "item_seq": clean(row["item_seq"]),
        "item_name": clean(row["item_name"]),
        "entp_name": clean(row["entp_name"]),
        "image_url": clean(row["item_image"]),
        # 일반/전문 구분 (허가정보 원문 그대로). rx_required는 앱 표시용: 전문의약품이면 True, 모르면 None
        "etc_otc": etc_otc_of(row["etc_otc"]),
        "rx_required": rx_required_of(row["etc_otc"]),
        "efficacy": clean(row["efcy_qesitm"]),
        "use_method": clean(row["use_method_qesitm"]),
        "warning": clean(row["atpn_warn_qesitm"]),
        "caution": clean(row["atpn_qesitm"]),
        "interaction": clean(row["intrc_qesitm"]),
        "side_effect": clean(row["se_qesitm"]),
        "storage": clean(row["deposit_method_qesitm"]),
        "open_date": norm_date(row["open_de"]),
        "update_date": norm_date(row["update_de"]),
    }
    drug["_key"] = squash(drug["item_name"] or "")
    drug["_efcy_key"] = squash(efficacy_body(drug["efficacy"]))
    return drug


# e약은요 효능 문장은 거의 다 "이 약은 …에 사용합니다." 꼴이라, 앞뒤 틀은 효능 검색에서 뺀다.
EFCY_HEAD = re.compile(r"^\s*이\s*약은\s*")
EFCY_TAIL = re.compile(r"\s*사용합니다\.?\s*$")


def efficacy_body(value):
    if not value:
        return ""
    return EFCY_TAIL.sub("", EFCY_HEAD.sub("", value))


def load_drugs():
    """서버가 켜질 때 약 목록을 DB에서 한 번 읽어 둔다."""
    try:
        with engine.connect() as conn:
            has_etc_otc = conn.execute(ETC_OTC_SQL).first() is not None
            rows = conn.execute(DRUG_SQL if has_etc_otc else DRUG_SQL_OLD).mappings().all()
    except ProgrammingError as exc:
        raise RuntimeError(
            "drugs 표를 찾을 수 없어요. README의 'DB 복원'을 먼저 하고, .env의 DB 이름을 확인하세요."
        ) from exc
    if not rows:
        raise RuntimeError("drugs 표가 비어 있어요. 김서현 님 백업(.dump)을 복원했는지 확인하세요.")
    # 약 목록은 서버가 켜질 때 한 번만 읽는다. DB를 바꿨으면 서버를 다시 켜야 한다. (고연수 10/26)
    LOAD_INFO.update({
        "drug_count": len(rows),
        "etc_otc_column": has_etc_otc,
        "loaded_at": dt.datetime.now().isoformat(timespec="seconds"),
    })
    if has_etc_otc:
        logger.info("약 %d건 읽음. 일반/전문 구분(etc_otc) 칸 있음.", len(rows))
    else:
        logger.warning("약 %d건 읽음. drugs.etc_otc 칸이 없어 일반/전문 구분(rx_required)은 모두 null로 나가요. "
                       "칸을 넣었다면 서버를 다시 켜세요.", len(rows))
    return [row_to_drug(r) for r in rows]


DRUGS = load_drugs()
DRUG_BY_SEQ = {d["item_seq"]: d for d in DRUGS}


class DrugSummary(BaseModel):
    item_seq: str
    item_name: str | None
    entp_name: str | None
    image_url: str | None
    etc_otc: str | None  # 일반의약품 / 전문의약품 / null(구분 없음)
    rx_required: bool | None  # 처방 필요 여부. 전문의약품 True, 일반의약품 False, 모르면 null
    source: str = "e약은요"


class DrugList(BaseModel):
    items: list[DrugSummary]
    page: int
    size: int
    total: int


class DrugDetail(BaseModel):
    item_seq: str
    item_name: str | None
    entp_name: str | None
    image_url: str | None
    etc_otc: str | None
    rx_required: bool | None
    efficacy: str | None
    use_method: str | None
    warning: str | None
    caution: str | None
    interaction: str | None
    side_effect: str | None
    storage: str | None
    open_date: str | None
    update_date: str | None
    source: str = "e약은요"


class EfficacyDrug(DrugSummary):
    efficacy: str | None  # e약은요 효능 원문 그대로
    matched: str | None  # 원문에서 검색어와 맞은 부분 (띄어쓰기 원문대로). 앱이 강조 표시에 쓴다


class EfficacyCounts(BaseModel):
    otc: int  # 일반의약품
    rx: int  # 전문의약품
    unknown: int  # 구분 없음


class EfficacyList(BaseModel):
    items: list[EfficacyDrug]
    page: int
    size: int
    total: int
    counts: EfficacyCounts  # 페이지와 상관없이 맞은 약 전체의 일반/전문 개수


def matched_text(efficacy, key):
    """띄어쓰기를 무시하고 맞은 부분을 원문 그대로 꺼낸다. (검색은 squash로 비교하므로)"""
    pattern = r"\s*".join(re.escape(ch) for ch in key)
    m = re.search(pattern, efficacy_body(efficacy), re.IGNORECASE)
    return m.group(0) if m else None


def search_efficacy(q, page, size):
    """효능 문장에 검색어가 들어간 약. 추천·순위가 아니므로 이름 가나다순으로만 늘어놓는다. (교수님 10/21 피드백 ③)"""
    key = squash(q)
    hits = [d for d in DRUGS if key and key in d["_efcy_key"]]
    hits.sort(key=lambda d: (d["_key"], d["item_seq"]))
    counts = {"otc": 0, "rx": 0, "unknown": 0}
    for d in hits:
        counts["unknown" if d["rx_required"] is None else "rx" if d["rx_required"] else "otc"] += 1
    start = (page - 1) * size
    items = [{**d, "matched": matched_text(d["efficacy"], key)} for d in hits[start:start + size]]
    return {"items": items, "page": page, "size": size, "total": len(hits), "counts": counts}


def search(q, page, size):
    key = squash(q)
    if not key:
        return {"items": [], "page": page, "size": size, "total": 0}
    hits = [d for d in DRUGS if key in d["_key"]]
    # 앞글자 일치를 먼저, 그다음 포함. 각각 이름이 짧은 순.
    hits.sort(key=lambda d: (not d["_key"].startswith(key), len(d["_key"]), d["_key"], d["item_seq"]))
    start = (page - 1) * size
    return {"items": hits[start:start + size], "page": page, "size": size, "total": len(hits)}


router = APIRouter(prefix="/api/v1", tags=["drugs"])


@router.get("/drugs", response_model=DrugList)
def search_drugs(
    q: str = Query(..., min_length=1),
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
):
    return search(q, page, size)


# /drugs/{item_seq}보다 먼저 둬야 'by-efficacy'가 약 번호로 잡히지 않는다.
@router.get("/drugs/by-efficacy", response_model=EfficacyList)
def search_drugs_by_efficacy(
    q: str = Query(..., min_length=1),
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
):
    return search_efficacy(q, page, size)


@router.get("/drugs/{item_seq}", response_model=DrugDetail)
def get_drug(item_seq: str):
    drug = DRUG_BY_SEQ.get(item_seq)
    if drug is None:
        raise HTTPException(status_code=404, detail="약을 찾을 수 없어요.")
    return drug
