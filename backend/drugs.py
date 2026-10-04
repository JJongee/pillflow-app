"""약 검색·상세 API. 김서현 DB의 drugs, drug_images 표에서 읽는다. (CSV는 더 이상 필요 없음)"""

import datetime as dt
import re

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.exc import ProgrammingError

from db import engine

DRUG_SQL = text(
    """
    SELECT d.item_seq, d.item_name, d.entp_name,
           d.efcy_qesitm, d.use_method_qesitm, d.atpn_warn_qesitm, d.atpn_qesitm,
           d.intrc_qesitm, d.se_qesitm, d.deposit_method_qesitm,
           d.open_de, d.update_de,
           (SELECT MIN(i.item_image) FROM drug_images i WHERE i.item_seq = d.item_seq) AS item_image
    FROM drugs d
    ORDER BY d.item_seq
    """
)


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


def row_to_drug(row):
    drug = {
        "item_seq": clean(row["item_seq"]),
        "item_name": clean(row["item_name"]),
        "entp_name": clean(row["entp_name"]),
        "image_url": clean(row["item_image"]),
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
    return drug


def load_drugs():
    """서버가 켜질 때 약 목록을 DB에서 한 번 읽어 둔다."""
    try:
        with engine.connect() as conn:
            rows = conn.execute(DRUG_SQL).mappings().all()
    except ProgrammingError as exc:
        raise RuntimeError(
            "drugs 표를 찾을 수 없어요. README의 'DB 복원'을 먼저 하고, .env의 DB 이름을 확인하세요."
        ) from exc
    if not rows:
        raise RuntimeError("drugs 표가 비어 있어요. 김서현 님 백업(.dump)을 복원했는지 확인하세요.")
    return [row_to_drug(r) for r in rows]


DRUGS = load_drugs()
DRUG_BY_SEQ = {d["item_seq"]: d for d in DRUGS}


class DrugSummary(BaseModel):
    item_seq: str
    item_name: str | None
    entp_name: str | None
    image_url: str | None
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


@router.get("/drugs/{item_seq}", response_model=DrugDetail)
def get_drug(item_seq: str):
    drug = DRUG_BY_SEQ.get(item_seq)
    if drug is None:
        raise HTTPException(status_code=404, detail="약을 찾을 수 없어요.")
    return drug
