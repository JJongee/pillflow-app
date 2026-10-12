"""시연에 쓰는 약들의 DUR 결과를 실제 서버에서 받아 목업 데이터(assets/mock/dur_rules.json)에 넣습니다.

사용법 (서버를 켜 둔 상태에서, 저장소 맨 위 폴더에서):
    backend\\.venv\\Scripts\\python.exe tools\\export_mock_dur.py

- 임시 계정을 하나 만들어 약을 등록하고 POST /dur/check 결과를 그대로 옮깁니다.
- 병용금기: 서버 findings(사유·성분·고시일 원문) / 참고 정보: 서버 cautions(5종, info 포함)
- 판정(applies)은 목업 앱이 임신 여부·성별에 따라 다시 계산하므로 저장하지 않습니다.
- 연령금기는 나이에 따라 달라서 기존 목업 규칙을 그대로 둡니다.
- 표준 라이브러리만 사용 (추가 설치 없음).
"""
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8000/api/v1"
RULES = Path(__file__).resolve().parent.parent / "assets" / "mock" / "dur_rules.json"

# 지금까지 시연·검수에 쓴 약 (item_seq: 이름)
DRUGS = {
    "199300273": "멕시롱액(돔페리돈)",
    "201706199": "코메키나캡슐",
    "202002383": "코트리나캡슐",
    "202500360": "코시원큐캡슐",
    "202106092": "타이레놀정500밀리그람",
    "198700405": "베아제정",
    "201308592": "사노바겔(리도카인)",
    "198300064": "아나프록스정(나프록센나트륨)",
    "200008591": "바이엘아스피린정500밀리그람",
    "197900277": "게보린정",
    "199902738": "에스로반연고",
    "200200774": "로푸록스겔",
    "195700020": "활명수",
}


def call(method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw else None)


def main():
    try:
        call("GET", "/auth/me")
    except urllib.error.URLError:
        sys.exit("서버에 연결할 수 없어요. backend 폴더에서 서버를 먼저 켜 주세요.")

    email = f"mockexport{int(time.time())}@pillflow.app"
    pw = "export1234"
    s, _ = call("POST", "/auth/signup", {"email": email, "password": pw})
    if s not in (200, 201):
        sys.exit(f"임시 계정을 만들지 못했어요 ({s}).")
    s, r = call("POST", "/auth/login", {"email": email, "password": pw})
    token = (r or {}).get("access_token")
    if not token:
        sys.exit(f"로그인 실패 ({s}).")

    for seq, name in DRUGS.items():
        s, _ = call("POST", "/me/drugs", {"item_seq": seq}, token)
        print(f"  등록 {'OK ' if s in (200, 201, 409) else s} {name}")

    s, res = call("POST", "/dur/check", {"item_seqs": list(DRUGS)}, token)
    if s != 200:
        sys.exit(f"/dur/check 실패 ({s}): {res}")

    rules = json.loads(RULES.read_text(encoding="utf-8"))
    ours = set(DRUGS)

    # 1) DUR 수집된 약 (판정 불가가 아닌 약)
    covered = set(rules.get("dur_covered_item_seqs", []))
    for d in res["drugs"]:
        seq = str(d["item_seq"])
        if d.get("verdict") != "UNDETERMINED":
            covered.add(seq)
        else:
            covered.discard(seq)
    rules["dur_covered_item_seqs"] = sorted(covered)

    # 2) 병용금기: 우리 약끼리의 기존 규칙은 서버 원문으로 교체
    combos = [
        c for c in rules.get("combination_rules", [])
        if not (c["a_item_seq"] in ours and c["b_item_seq"] in ours)
    ]
    for f in res.get("findings", []):
        if f.get("type") != "COMBINATION" or len(f.get("item_seqs", [])) != 2:
            continue
        a, b = (str(x) for x in f["item_seqs"])
        ing = f.get("ingredients") or []
        combos.append({
            "a_item_seq": a,
            "b_item_seq": b,
            "ingredient_a": ing[0] if len(ing) > 0 else None,
            "ingredient_b": ing[1] if len(ing) > 1 else None,
            "detail": f.get("detail") or "",
            "condition_note": f.get("condition_note"),
            "notice_no": f.get("notice_no"),
            "notice_date": f.get("notice_date"),
        })
    rules["combination_rules"] = combos

    # 3) 참고 정보: 우리 약의 기존 항목은 서버 원문으로 교체 (판정은 목업이 다시 계산)
    cautions = [
        c for c in rules.get("cautions", [])
        if not any(str(x) in ours for x in c.get("item_seqs", []))
    ]
    for c in res.get("cautions", []):
        c = {k: v for k, v in c.items() if k not in ("applies", "applies_note")}
        cautions.append(c)
    rules["cautions"] = cautions

    rules["_comment"] = (
        "목업 전용. 실제 판별은 서버가 DB로 수행. 시연 약들의 병용금기·참고 정보는 "
        f"tools/export_mock_dur.py로 실제 서버 응답을 옮김 ({time.strftime('%Y-%m-%d')}, "
        f"{res.get('data_version')}). 연령금기는 게시 2609 파일 실제 행."
    )
    RULES.write_text(json.dumps(rules, ensure_ascii=False, indent=1), encoding="utf-8")

    print()
    print(f"완료: 병용금기 {len(combos)}건, 참고 정보 {len(cautions)}건, DUR 수집 약 {len(covered)}개")
    print(f"저장: {RULES}")
    print(f"(임시 계정 {email} 은 로컬 DB에만 남아요)")


if __name__ == "__main__":
    main()
