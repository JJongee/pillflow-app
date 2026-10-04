"""필플로우 서버 자동 점검 (10/8 통합 테스트, 10/10 권한·잘못된 입력 점검용)

사용법: 서버를 켜 둔 상태에서, 다른 PowerShell 창의 backend 폴더에서
    python check_api.py
다른 주소의 서버를 점검하려면
    python check_api.py http://192.168.0.10:8000/api/v1

추가 설치 없이 파이썬 기본 기능만 씁니다.
점검용 계정 2개(check_시각_a/b@test.com)가 DB에 남습니다. 등록한 약·시간표는 마지막에 지웁니다.
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:8000/api/v1"
ROOT = BASE.rsplit("/api/", 1)[0]

passed = failed = 0


def call(method, path, body=None, token=None, params=None, base=BASE):
    url = base + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            raw = res.read().decode("utf-8")
            return res.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


def check(name, cond, info=""):
    """cond는 참/거짓 또는 함수. 응답 모양이 달라 오류가 나도 '실패'로 표시하고 계속한다."""
    global passed, failed
    try:
        ok = cond() if callable(cond) else cond
    except Exception as e:  # noqa: BLE001
        ok, info = False, f"{info} ({type(e).__name__}: {e})"
    if ok:
        passed += 1
        print(f"  통과  {name}")
    else:
        failed += 1
        print(f"  실패  {name}  {info}")


def code_of(body):
    return body.get("code") if isinstance(body, dict) else None


print(f"점검 대상: {BASE}\n")

# ---------- 0. 서버 연결 ----------
print("[0] 서버 연결")
try:
    s, b = call("GET", "/", base=ROOT)
except urllib.error.URLError as e:
    print(f"  실패  서버에 연결할 수 없어요. 서버를 켰는지 확인하세요. ({e.reason})")
    sys.exit(1)
check("GET / 응답", s == 200, s)

# ---------- 1. 약 검색·상세 ----------
print("[1] 약 검색·상세")
s, b = call("GET", "/drugs", params={"q": "타이레놀"})
check("검색 '타이레놀' 7건", lambda: s == 200 and b["total"] == 7, (s, b.get("total") if isinstance(b, dict) else b))
s, b = call("GET", "/drugs", params={"q": "타이 레놀", "size": 2})
check("띄어쓰기 무시 + 페이지 크기 2", lambda: s == 200 and b["total"] == 7 and len(b["items"]) == 2, s)
s, b = call("GET", "/drugs")
check("검색어 없이 → 422 VALIDATION_ERROR", lambda: s == 422 and code_of(b) == "VALIDATION_ERROR", (s, code_of(b)))
s, b = call("GET", "/drugs", params={"q": "타이레놀", "size": 101})
check("페이지 크기 101 → 422", lambda: s == 422, s)
s, b = call("GET", "/drugs/202106092")
check("상세 202106092 (날짜 YYYY-MM-DD)", lambda: s == 200 and b["update_date"] == "2026-06-29" and b["open_date"] == "2023-05-31", s)
s, b = call("GET", "/drugs/0000")
check("없는 약 → 404 NOT_FOUND", lambda: s == 404 and code_of(b) == "NOT_FOUND", (s, code_of(b)))

# ---------- 2. 가입·로그인 ----------
print("[2] 가입·로그인")
stamp = time.strftime("%m%d%H%M%S")
email_a, email_b, pw = f"check_{stamp}_a@test.com", f"check_{stamp}_b@test.com", "check1234"
s, b = call("POST", "/auth/signup", {"email": email_a, "password": pw})
check("가입 → 201", lambda: s == 201, (s, b))
s, b = call("POST", "/auth/signup", {"email": email_a.upper(), "password": pw})
check("같은 이메일(대문자) 다시 가입 → 409 DUPLICATE", lambda: s == 409 and code_of(b) == "DUPLICATE", (s, code_of(b)))
s, b = call("POST", "/auth/signup", {"email": "not-an-email", "password": pw})
check("이메일 형식 오류 → 422", lambda: s == 422, s)
s, b = call("POST", "/auth/signup", {"email": f"x{stamp}@test.com", "password": "12"})
check("비밀번호 너무 짧음 → 422", lambda: s == 422, s)
s, b = call("POST", "/auth/login", {"email": email_a, "password": "wrong"})
check("틀린 비밀번호 → 401 UNAUTHORIZED", lambda: s == 401 and code_of(b) == "UNAUTHORIZED", (s, code_of(b)))
s, b = call("POST", "/auth/login", {"email": email_a, "password": pw})
check("로그인 → 토큰", lambda: s == 200 and b.get("token_type") == "bearer" and b.get("access_token"), s)
token_a = b.get("access_token") if isinstance(b, dict) else None
s, b = call("POST", "/auth/login", {"email": "demo@pillflow.app", "password": "1234"})
check("데모 계정 로그인", lambda: s == 200, s)

# ---------- 3. 권한 ----------
print("[3] 권한")
s, b = call("GET", "/me/drugs")
check("토큰 없이 내 약 → 401", lambda: s == 401, s)
s, b = call("GET", "/me/drugs", token="abc.def.ghi")
check("가짜 토큰 → 401", lambda: s == 401, s)
s, b = call("POST", "/dur/check", {"item_seqs": ["199300273"]})
check("토큰 없이 DUR → 401", lambda: s == 401, s)

# ---------- 4. 내 약 ----------
print("[4] 내 약")
s, b = call("POST", "/me/drugs", {"item_seq": "199300273", "memo": "점검"}, token_a)
check("등록 → 201", lambda: s == 201 and b["item_name"].startswith("멕시롱"), (s, b))
drug1 = b.get("id") if isinstance(b, dict) else None
s, b = call("POST", "/me/drugs", {"item_seq": "199300273"}, token_a)
check("같은 약 다시 등록 → 409 DUPLICATE", lambda: s == 409 and code_of(b) == "DUPLICATE", (s, code_of(b)))
s, b = call("POST", "/me/drugs", {"item_seq": "0000"}, token_a)
check("없는 약 등록 → 404", lambda: s == 404, s)
s, b = call("POST", "/me/drugs", {"item_seq": "201706199"}, token_a)
check("두 번째 약 등록 → 201", lambda: s == 201, s)
drug2 = b.get("id") if isinstance(b, dict) else None
s, b = call("GET", "/me/drugs", token=token_a)
check("목록 2개 (YYYY-MM-DD 날짜)", lambda: s == 200 and len(b) == 2 and len(b[0]["created_at"]) == 10, s)
s, b = call("PATCH", f"/me/drugs/{drug1}", {"memo": "저녁"}, token_a)
check("메모 수정", lambda: s == 200 and b["memo"] == "저녁", s)

# ---------- 5. 시간표·복용 기록 ----------
print("[5] 시간표·복용 기록")
s, b = call("POST", "/me/schedules", {"user_drug_id": drug1, "time": "8:30", "meal_relation": "AFTER"}, token_a)
check("시간 형식 오류(8:30) → 422", lambda: s == 422, s)
s, b = call("POST", "/me/schedules", {"user_drug_id": drug1, "time": "08:30", "meal_relation": "LUNCH"}, token_a)
check("식사 관계 오류(LUNCH) → 422", lambda: s == 422, s)
s, b = call("POST", "/me/schedules", {"user_drug_id": drug1, "time": "08:30", "meal_relation": "AFTER", "dose_text": "1포"}, token_a)
check("시간표 추가 → 201", lambda: s == 201 and b["time"] == "08:30", (s, b))
sched = b.get("id") if isinstance(b, dict) else None
today = time.strftime("%Y-%m-%d")
s, b = call("GET", "/me/intakes", token=token_a, params={"date": today})
check("오늘 복용 현황 → PENDING", lambda: s == 200 and len(b) == 1 and b[0]["status"] == "PENDING", s)
s, b = call("PUT", "/me/intakes", {"schedule_id": sched, "date": today, "status": "TAKEN"}, token_a)
check("먹었어요 기록 → TAKEN", lambda: s == 200 and b["status"] == "TAKEN" and b["recorded_at"], s)
s, b = call("GET", "/me/intakes", token=token_a, params={"date": "2026-13-01"})
check("없는 날짜 → 422", lambda: s == 422, s)

# ---------- 6. 다른 사용자 차단 ----------
print("[6] 다른 사용자 차단")
call("POST", "/auth/signup", {"email": email_b, "password": pw})
s, b = call("POST", "/auth/login", {"email": email_b, "password": pw})
token_b = b.get("access_token") if isinstance(b, dict) else None
s, b = call("GET", "/me/drugs", token=token_b)
check("B는 A의 약이 안 보임", lambda: s == 200 and b == [], (s, b))
s, b = call("PATCH", f"/me/drugs/{drug1}", {"memo": "해킹"}, token_b)
check("B가 A의 약 수정 → 404", lambda: s == 404, s)
s, b = call("DELETE", f"/me/drugs/{drug1}", token=token_b)
check("B가 A의 약 삭제 → 404", lambda: s == 404, s)
s, b = call("PUT", "/me/intakes", {"schedule_id": sched, "date": today, "status": "SKIPPED"}, token_b)
check("B가 A의 복용 기록 변경 → 404", lambda: s == 404, s)
s, b = call("POST", "/me/schedules", {"user_drug_id": drug1, "time": "09:00"}, token_b)
check("B가 A의 약으로 시간표 추가 → 404", lambda: s == 404, s)

# ---------- 7. DUR 병용금기 ----------
print("[7] DUR 병용금기")
s, b = call("POST", "/dur/check", {}, token_a)
ok = lambda: s == 200 and [d["verdict"] for d in b["drugs"]] == ["CONTRAINDICATED", "CONTRAINDICATED"] and len(b["findings"]) == 1
check("내 약 전체(멕시롱액+코메키나) → 금기 1건", ok, s)
first = b.get("findings") if isinstance(b, dict) else None
s, b = call("POST", "/dur/check", {"item_seqs": ["201706199", "199300273"]}, token_a)
check("순서 바꿔도 같은 금기", lambda: s == 200 and b["findings"] == first, s)
s, b = call("POST", "/dur/check", {"item_seqs": ["202106092", "199300273"]}, token_a)
check("기록 없음 → NO_KNOWN_ISSUE (안전 아님)", lambda: s == 200 and {d["verdict"] for d in b["drugs"]} == {"NO_KNOWN_ISSUE"} and b["findings"] == [], s)
s, b = call("POST", "/dur/check", {"item_seqs": ["202106092", "EDI-1"]}, token_a)
ok = lambda: s == 200 and b["drugs"][1]["verdict"] == "UNDETERMINED" and isinstance(b["drugs"][1]["item_name"], str)
check("모르는 번호 → UNDETERMINED (이름은 글자)", ok, s)
s, b = call("POST", "/dur/check", {"item_seqs": []}, token_a)
check("빈 목록 → 422", lambda: s == 422, s)

# ---------- 8. 프로필 ----------
print("[8] 프로필")
s, b = call("PUT", "/me/profile", {"birth_year": 1960}, token_a)
check("태어난 해 저장", lambda: s == 200 and b["birth_year"] == 1960, s)
s, b = call("POST", "/dur/check", {}, token_a)
check("태어난 해가 있으면 age_unknown=false", lambda: s == 200 and b["age_unknown"] is False, s)
s, b = call("PUT", "/me/profile", {"birth_year": 1800}, token_a)
check("말이 안 되는 해(1800) → 422", lambda: s == 422, s)

# ---------- 9. 삭제와 정리 ----------
print("[9] 삭제와 정리")
s, b = call("DELETE", f"/me/drugs/{drug1}", token=token_a)
check("약 삭제 → 204", lambda: s == 204, s)
s, b = call("GET", "/me/schedules", token=token_a)
check("약을 지우면 시간표도 같이 삭제", lambda: s == 200 and b == [], (s, b))
s, b = call("DELETE", f"/me/drugs/{drug2}", token=token_a)
check("남은 약 정리 → 204", lambda: s == 204, s)

print(f"\n결과: 통과 {passed}개, 실패 {failed}개")
sys.exit(1 if failed else 0)
