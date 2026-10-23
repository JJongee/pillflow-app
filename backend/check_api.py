"""필플로우 서버 자동 점검 (10/8 통합 테스트, 10/10 권한·잘못된 입력 점검용)

사용법: 서버를 켜 둔 상태에서, 다른 PowerShell 창의 backend 폴더에서
    python check_api.py
다른 주소의 서버를 점검하려면
    python check_api.py http://192.168.0.10:8000/api/v1

추가 설치 없이 파이썬 기본 기능만 씁니다.
점검용 계정 2개(check_시각_a/b@test.com)가 DB에 남습니다. 등록한 약·시간표는 마지막에 지웁니다.
"""

import datetime as dt
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
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        # 서버가 꺼졌거나(연결 거부) 멈춰서 대답이 없을 때(시간 초과)
        return 0, f"서버 응답 없음: {getattr(e, 'reason', e)}"


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
s, b = call("GET", "/", base=ROOT)
if s == 0:
    print(f"  실패  {b}")
    print("        서버를 켰는지, 서버 창이 '선택' 상태로 멈춰 있지 않은지(창에서 Esc) 확인하세요.")
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
# 1회 복용량 숫자 + 단위 (고연수·손채은 요청, 10/10 추가). 서버는 기록만 하고 판정하지 않는다.
sched0 = b.get("id") if isinstance(b, dict) else None
check("복용량을 안 보내면 null", lambda: b.get("dose_amount") is None and b.get("dose_unit") is None, (b.get("dose_amount"), b.get("dose_unit")))
s, b = call("PATCH", f"/me/schedules/{sched0}", {"dose_amount": 1.5, "dose_unit": "정"}, token_a)
check("복용량 숫자 + 단위 저장", lambda: s == 200 and b["dose_amount"] == 1.5 and b["dose_unit"] == "정", (s, b))
s, b = call("GET", "/me/schedules", token=token_a)
check("목록에도 복용량이 남아 있음", lambda: s == 200 and any(x["dose_amount"] == 1.5 for x in b), s)
s, b = call("PATCH", f"/me/schedules/{sched0}", {"dose_amount": None, "dose_unit": None}, token_a)
check("복용량을 null로 지울 수 있음", lambda: s == 200 and b["dose_amount"] is None and b["dose_unit"] is None, (s, b))
s, b = call("PATCH", f"/me/schedules/{sched0}", {"dose_amount": 0}, token_a)
check("복용량 0 → 422", lambda: s == 422, s)
s, b = call("PATCH", f"/me/schedules/{sched0}", {"dose_amount": -1}, token_a)
check("복용량 음수 → 422", lambda: s == 422, s)
s, b = call("PATCH", f"/me/schedules/{sched0}", {"dose_unit": "알"}, token_a)
check("목록에 없는 단위 → 422 (앱은 직접 입력으로 dose_text에 넣음)", lambda: s == 422, s)
s, b = call("PATCH", f"/me/schedules/{sched0}", {"dose_text": "반 봉지"}, token_a)
check("목록에 없는 단위는 dose_text로는 들어감", lambda: s == 200 and b["dose_text"] == "반 봉지" and b["dose_unit"] is None, (s, b))
s, b = call("POST", "/me/schedules", {"user_drug_id": drug1, "time": "21:00", "dose_amount": 0.5, "dose_unit": "mL"}, token_a)
check("만들 때 바로 복용량 넣기 (0.5 mL)", lambda: s == 201 and b["dose_amount"] == 0.5 and b["dose_unit"] == "mL", (s, b))
call("DELETE", f"/me/schedules/{b.get('id')}", token=token_a)  # 복용량 점검용은 정리
sched = sched0  # 복용 기록은 맨 처음 만든 08:30 시간표로 본다
today = time.strftime("%Y-%m-%d")
s, b = call("GET", "/me/intakes", token=token_a, params={"date": today})
check("오늘 복용 현황 → PENDING", lambda: s == 200 and len(b) == 1 and b[0]["status"] == "PENDING", s)
s, b = call("PUT", "/me/intakes", {"schedule_id": sched, "date": today, "status": "TAKEN"}, token_a)
check("먹었어요 기록 → TAKEN", lambda: s == 200 and b["status"] == "TAKEN" and b["recorded_at"], s)
s, b = call("GET", "/me/intakes", token=token_a, params={"date": "2026-13-01"})
check("없는 날짜 → 422", lambda: s == 422, s)

# ---------- 5-1. 기간 복용 요약 (달력·이번 주 줄, 고연수 10/22) ----------
print("[5-1] 기간 복용 요약")
import datetime as _dt  # noqa: E402
_today = _dt.date.fromisoformat(today)
_d = lambda n: (_today + _dt.timedelta(days=n)).isoformat()
s, b = call("GET", "/me/intakes/summary", params={"from": _d(-7), "to": _d(1)})
check("토큰 없이 요약 → 401", lambda: s == 401, s)
s, b = call("GET", "/me/intakes/summary", token=token_a, params={"from": _d(-7), "to": _d(1)})
check("9일 조회 → 날짜마다 한 줄 (빈 날도 포함)", lambda: s == 200 and [x["date"] for x in b] == [_d(n) for n in range(-7, 2)], (s, b))
_by = {x["date"]: x for x in b} if isinstance(b, list) else {}
check("오늘: 1개 중 1개 먹음 → ALL_TAKEN", lambda: _by[today]["scheduled"] == 1 and _by[today]["taken"] == 1 and _by[today]["day_status"] == "ALL_TAKEN", _by.get(today))
check("시간표 만들기 전 날 → NO_DRUG ('안 먹음' 아님)", lambda: _by[_d(-1)]["scheduled"] == 0 and _by[_d(-1)]["day_status"] == "NO_DRUG", _by.get(_d(-1)))
check("내일 → UPCOMING (시간표 1개, pending 1)", lambda: _by[_d(1)]["day_status"] == "UPCOMING" and _by[_d(1)]["pending"] == 1, _by.get(_d(1)))
s, b = call("GET", "/me/intakes/summary", token=token_a, params={"from": _d(1), "to": _d(0)})
check("to가 from보다 빠르면 → 422", lambda: s == 422, s)
s, b = call("GET", "/me/intakes/summary", token=token_a, params={"from": _d(0), "to": _d(93)})
check("94일 조회 → 422 (최대 93일)", lambda: s == 422, s)

# ---------- 4-1. 직접 추가 항목 (영양제 등, 고연수 10/23) ----------
print("[4-1] 직접 추가 항목 (영양제 등)")
s, b = call("POST", "/me/drugs", {"custom_name": "오메가3", "kind": "SUPPLEMENT", "memo": "아침"}, token_a)
check("이름만으로 등록 → 201, is_custom=true, item_seq=null", lambda: s == 201 and b["is_custom"] is True and b["item_seq"] is None and b["kind"] == "SUPPLEMENT", (s, b))
custom1 = b.get("id") if isinstance(b, dict) else None
check("item_name에는 적은 이름이 들어감", lambda: b["item_name"] == "오메가3" and b["custom_name"] == "오메가3", b.get("item_name"))
s, b = call("POST", "/me/drugs", {"custom_name": "오메가3"}, token_a)
check("같은 이름 다시 추가 → 409 DUPLICATE", lambda: s == 409 and code_of(b) == "DUPLICATE", (s, code_of(b)))
s, b = call("POST", "/me/drugs", {"custom_name": "비타민D"}, token_a)
check("kind를 안 보내면 OTHER", lambda: s == 201 and b["kind"] == "OTHER", (s, b.get("kind") if isinstance(b, dict) else b))
custom2 = b.get("id") if isinstance(b, dict) else None
s, b = call("POST", "/me/drugs", {"memo": "아무것도 없음"}, token_a)
check("item_seq도 custom_name도 없으면 → 422", lambda: s == 422, s)
s, b = call("POST", "/me/drugs", {"item_seq": "199300273", "custom_name": "둘 다"}, token_a)
check("둘 다 보내면 → 422", lambda: s == 422, s)
s, b = call("POST", "/me/drugs", {"custom_name": "루테인", "kind": "FOOD"}, token_a)
check("정해진 kind가 아니면 → 422", lambda: s == 422, s)
s, b = call("GET", "/me/drugs", token=token_a)
check("목록에서 약 목록의 약은 is_custom=false, 직접 추가는 true", lambda: s == 200 and {x["is_custom"] for x in b if x["id"] in (drug1, drug2)} == {False} and {x["is_custom"] for x in b if x["id"] in (custom1, custom2)} == {True}, s)
s, b = call("PATCH", f"/me/drugs/{custom1}", {"custom_name": "오메가3 1000", "kind": "MEDICINE"}, token_a)
check("직접 추가 항목은 이름·종류 수정 가능", lambda: s == 200 and b["item_name"] == "오메가3 1000" and b["kind"] == "MEDICINE", (s, b))
s, b = call("PATCH", f"/me/drugs/{drug1}", {"custom_name": "바꿈"}, token_a)
check("약 목록의 약은 이름 수정 → 422", lambda: s == 422, s)
s, b = call("PATCH", f"/me/drugs/{custom1}", {"custom_name": None}, token_a)
check("직접 추가 이름을 null로 지우기 → 422", lambda: s == 422, s)
s, b = call("POST", "/me/schedules", {"user_drug_id": custom1, "time": "09:00", "dose_text": "1캡슐"}, token_a)
check("직접 추가 항목에 시간표 추가 → 201, 이름은 적은 이름", lambda: s == 201 and b["item_name"] == "오메가3 1000", (s, b))
custom_sched = b.get("id") if isinstance(b, dict) else None
s, b = call("GET", "/me/intakes", token=token_a, params={"date": today})
check("오늘 복용 현황에 직접 추가 항목도 보임 (2개)", lambda: s == 200 and len(b) == 2 and any(x["item_name"] == "오메가3 1000" for x in b), s)
s, b = call("PUT", "/me/intakes", {"schedule_id": custom_sched, "date": today, "status": "TAKEN"}, token_a)
check("직접 추가 항목 복용 기록 → TAKEN", lambda: s == 200 and b["status"] == "TAKEN", s)
s, b = call("GET", "/me/intakes/summary", token=token_a, params={"from": today, "to": today})
check("달력 요약에도 들어감 (2개 중 2개 → ALL_TAKEN)", lambda: s == 200 and b[0]["scheduled"] == 2 and b[0]["day_status"] == "ALL_TAKEN", (s, b))
s, b = call("POST", "/dur/check", {}, token_a)
check("DUR 내 약 전체: 직접 추가 2개는 빠지고 excluded_custom_count=2", lambda: s == 200 and len(b["drugs"]) == 2 and b["excluded_custom_count"] == 2, (s, b.get("excluded_custom_count") if isinstance(b, dict) else b))
check("DUR 안내에 '확인 대상이 아니에요'", lambda: any("확인 대상이 아니에요" in n for n in b["notes"]), b.get("notes"))
s, b = call("POST", "/me/schedules/suggest", None, token_a)
check("자동 제안: 직접 추가는 빠지고 excluded_custom_count=2", lambda: s == 200 and b["excluded_custom_count"] == 2 and all(x["item_seq"] for x in b["suggestions"]), (s, b.get("excluded_custom_count") if isinstance(b, dict) else b))
s, b = call("DELETE", f"/me/drugs/{custom1}", token=token_a)
check("직접 추가 항목 삭제 → 204 (시간표·기록도 같이)", lambda: s == 204, s)
call("DELETE", f"/me/drugs/{custom2}", token=token_a)
s, b = call("POST", "/dur/check", {}, token_a)
check("직접 추가가 없으면 excluded_custom_count=0", lambda: s == 200 and b["excluded_custom_count"] == 0, s)

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
s, b = call("PUT", "/me/profile", {"birth_date": "1958-03-15"}, token_a)
check("생년월일 저장 → 태어난 해도 같이 맞춤", lambda: s == 200 and b["birth_date"] == "1958-03-15" and b["birth_year"] == 1958, (s, b))
s, b = call("GET", "/me/profile", token=token_a)
check("프로필에 생년월일이 남아 있음", lambda: s == 200 and b["birth_date"] == "1958-03-15", (s, b))
s, b = call("PUT", "/me/profile", {"birth_date": "2030-01-01"}, token_a)
check("미래 생년월일 → 422", lambda: s == 422, s)
s, b = call("PUT", "/me/profile", {"birth_date": "1958-3-15"}, token_a)
check("날짜 형식 오류(1958-3-15) → 422", lambda: s == 422, s)
s, b = call("PUT", "/me/profile", {"birth_year": 1970}, token_a)
check("태어난 해만 바꾸면 어긋난 생년월일은 지워짐", lambda: s == 200 and b["birth_year"] == 1970 and b["birth_date"] is None, (s, b))
s, b = call("PUT", "/me/profile", {"birth_date": None, "birth_year": None}, token_a)
check("둘 다 비우기", lambda: s == 200 and b["birth_year"] is None and b["birth_date"] is None, (s, b))

# ---------- 9. 삭제와 정리 ----------
print("[9] 삭제와 정리")
s, b = call("DELETE", f"/me/drugs/{drug1}", token=token_a)
check("약 삭제 → 204", lambda: s == 204, s)
s, b = call("GET", "/me/schedules", token=token_a)
check("약을 지우면 시간표도 같이 삭제", lambda: s == 200 and b == [], (s, b))
s, b = call("DELETE", f"/me/drugs/{drug2}", token=token_a)
check("남은 약 정리 → 204", lambda: s == 204, s)

# ---------- 10. 검색 목록 안의 병용금기 15쌍 (김서현 DB 기준) ----------
print("[10] 병용금기 15쌍 (양방향)")
DOMPERIDONE = {"199300273": "멕시롱액", "199600830": "그린큐액", "199601110": "크리맥액"}
PARTNERS = {"201706199": "코메키나캡슐", "202002383": "코트리나캡슐", "202500360": "코시원큐캡슐",
            "202500864": "코코엔캡슐", "202501617": "액티플루노즈캡슐"}
for a, name_a in DOMPERIDONE.items():
    for c, name_c in PARTNERS.items():
        s1, b1 = call("POST", "/dur/check", {"item_seqs": [a, c]}, token_a)
        s2, b2 = call("POST", "/dur/check", {"item_seqs": [c, a]}, token_a)
        ok = lambda: (
            s1 == 200 and s2 == 200
            and {d["verdict"] for d in b1["drugs"]} == {"CONTRAINDICATED"}
            and {d["verdict"] for d in b2["drugs"]} == {"CONTRAINDICATED"}
            and len(b1["findings"]) >= 1 and b1["findings"] == b2["findings"]
        )
        verdicts = [d.get("verdict") for d in b1.get("drugs", [])] if isinstance(b1, dict) else b1
        check(f"{name_a}({a}) + {name_c}({c}) → 금기, 순서 바꿔도 같음", ok, (s1, s2, verdicts))

# ---------- 11. 연령금기 (김서현 DB 2차 백업 이후) ----------
print("[11] 연령금기")
AGE_DRUG = "202200407"  # 타이레놀8시간이알서방정, 12세 미만 금기
this_year = int(time.strftime("%Y"))
call("PUT", "/me/profile", {"birth_year": this_year - 5}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": [AGE_DRUG]}, token_a)
ok = lambda: (
    s == 200 and b["drugs"][0]["verdict"] == "CONTRAINDICATED"
    and any(f["type"] == "AGE" and "12세 미만" in f["detail"] for f in b["findings"])
)
check("5세 사용자 + 12세 미만 금기 약 → 연령금기", ok, (s, b.get("findings") if isinstance(b, dict) else b))
call("PUT", "/me/profile", {"birth_year": 1960}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": [AGE_DRUG]}, token_a)
check("성인 사용자 → 연령금기 없음", lambda: s == 200 and not any(f["type"] == "AGE" for f in b["findings"]), s)
call("PUT", "/me/profile", {"birth_year": None, "birth_date": None}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": [AGE_DRUG]}, token_a)
check("태어난 해 없음 → age_unknown, 연령금기 판단 안 함", lambda: s == 200 and b["age_unknown"] is True and not any(f["type"] == "AGE" for f in b["findings"]), s)
# 생년월일을 알면 생일에 따라 갈리는 경계도 정확히 판단한다
born = f"{this_year - 12}-12-01"  # 아직 12번째 생일 전
call("PUT", "/me/profile", {"birth_date": born}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": [AGE_DRUG]}, token_a)
age_notes = [f["condition_note"] or "" for f in b.get("findings", []) if f["type"] == "AGE"] if isinstance(b, dict) else []
ok = lambda: (
    s == 200 and b["age_unknown"] is False and b["drugs"][0]["verdict"] == "CONTRAINDICATED"
    and age_notes and all("생일에 따라" not in n for n in age_notes)
)
check("생년월일이 있으면 '생일에 따라' 안내 없이 확정", ok, (s, age_notes))
call("PUT", "/me/profile", {"birth_year": this_year - 12, "birth_date": None}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": [AGE_DRUG]}, token_a)
age_notes = [f["condition_note"] or "" for f in b.get("findings", []) if f["type"] == "AGE"] if isinstance(b, dict) else []
check("태어난 해만 알면 '생일에 따라' 안내가 붙음", lambda: s == 200 and any("생일에 따라" in n for n in age_notes), (s, age_notes))

# ---------- 12. 임부금기·용량주의 참고 정보 (김서현 DB 3차 백업 이후) ----------
print("[12] 임부금기·용량주의 (cautions)")
s, b = call("POST", "/dur/check", {"item_seqs": ["202106092"]}, token_a)
ok = lambda: (
    s == 200 and b["drugs"][0]["verdict"] == "NO_KNOWN_ISSUE"
    and any(c["type"] == "DOSE" and c["status"] == "CONFIRMED" and "4,000" in c["detail"] for c in b["cautions"])
)
check("타이레놀정500 → 용량주의(1일 4,000mg), 판정은 그대로", ok, (s, b.get("cautions") if isinstance(b, dict) else b))
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)
ok = lambda: s == 200 and any(c["type"] == "PREGNANCY" and c["grade"] == "2등급" for c in b["cautions"]) and b["findings"] == []
check("샤젠캡슐 → 임부금기 2등급 (findings에는 안 들어감)", ok, s)
s, b = call("POST", "/dur/check", {"item_seqs": ["200003488"]}, token_a)
check("기준 확인 중인 임부금기도 빠지지 않음", lambda: s == 200 and any(c["status"] == "PENDING" for c in b["cautions"]), s)

# ---------- 12-1. 노인주의·효능군중복주의·투여기간주의 (김서현 DB 10/6 검토본) ----------
print("[12-1] 노인주의·효능군중복·투여기간")
s, b = call("POST", "/dur/check", {"item_seqs": ["196000011"]}, token_a)  # 페니라민정
cautions = b.get("cautions", []) if isinstance(b, dict) else []
eld = [c for c in cautions if c["type"] == "ELDERLY"]
ok = lambda: s == 200 and eld and eld[0]["status"] == "CONFIRMED" and eld[0]["info"].get("성분") and b["drugs"][0]["verdict"] == "NO_KNOWN_ISSUE"
check("페니라민정 → 노인주의, 판정은 그대로", ok, (s, eld))
check("노인주의는 원문에 주의 내용이 없어 빈 줄을 넣지 않음", lambda: eld and "주의 내용" not in eld[0]["info"], eld[0]["info"] if eld else None)
check("대신 '원본에 상세 주의내용이 제공되지 않았어요'로 알림", lambda: eld and "원본에 상세 주의내용이 제공되지 않았어요" in (eld[0]["condition_note"] or ""), eld[0]["condition_note"] if eld else None)
dup = [c for c in cautions if c["type"] == "DUPLICATE"]
check("효능군중복 → 효능군·계열을 따로 돌려줌", lambda: dup and dup[0]["info"].get("효능군") and dup[0]["info"].get("계열"), dup[0]["info"] if dup else None)
check("효능군이 같다고 중복으로 단정하지 않는다는 안내", lambda: any("따로 확인" in n for n in b["notes"]), b.get("notes"))
s, b = call("POST", "/dur/check", {"item_seqs": ["197600483"]}, token_a)  # 비사코딜, 7일
dur_c = [c for c in b.get("cautions", []) if c["type"] == "DURATION"] if isinstance(b, dict) else []
check("투여기간 → 기간 원문 그대로 (7일)", lambda: dur_c and dur_c[0]["info"].get("기간 기준") == "7일", dur_c[0]["info"] if dur_c else None)
s, b = call("POST", "/dur/check", {"item_seqs": ["200200414"]}, token_a)  # linked·pending 둘 다
states = {c["status"] for c in b.get("cautions", []) if c["type"] == "DURATION"} if isinstance(b, dict) else set()
check("한 약에 linked와 pending이 같이 있으면 둘 다 남김", lambda: states == {"CONFIRMED", "PENDING"}, states)
s, b = call("POST", "/dur/check", {"item_seqs": ["196000011"]}, token_a)
check("새 3종도 판정(verdict)은 바꾸지 않음", lambda: s == 200 and b["drugs"][0]["verdict"] != "CONTRAINDICATED", s)

# ---------- 12-2. 임부금기·투여기간주의 판정 (손채은 10/11 요청) ----------
print("[12-2] 임부금기·투여기간 판정")
s, b = call("GET", "/me/profile", token=token_a)
check("프로필에 임신 여부가 있고 기본값은 UNKNOWN", lambda: s == 200 and b["pregnancy"] == "UNKNOWN", (s, b))
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)  # 샤젠캡슐, 임부금기 2등급
preg = [c for c in b.get("cautions", []) if c["type"] == "PREGNANCY"] if isinstance(b, dict) else []
ok = lambda: s == 200 and b["pregnancy"] == "UNKNOWN" and preg and preg[0]["applies"] == "UNKNOWN"
check("임신 여부 없으면 판정 UNKNOWN", ok, (s, preg[0]["applies"] if preg else None))
s, b = call("PUT", "/me/profile", {"pregnancy": "NOT_PREGNANT"}, token_a)
check("임신 여부 저장", lambda: s == 200 and b["pregnancy"] == "NOT_PREGNANT", (s, b))
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)
preg = [c for c in b.get("cautions", []) if c["type"] == "PREGNANCY"] if isinstance(b, dict) else []
check("임신 아님 → 해당 안 됨(NO)", lambda: preg and preg[0]["applies"] == "NO", preg[0]["applies"] if preg else None)
s, b = call("PUT", "/me/profile", {"pregnancy": "PREGNANT"}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)
preg = [c for c in b.get("cautions", []) if c["type"] == "PREGNANCY"] if isinstance(b, dict) else []
ok = lambda: preg and preg[0]["applies"] == "YES" and preg[0]["status"] == "CONFIRMED" and preg[0]["applies_note"]
check("임신 중 + 기준 확인됨 → 해당됨(YES), 상태와 판정은 별개 칸", ok, (preg[0]["status"], preg[0]["applies"]) if preg else None)
s, b = call("POST", "/dur/check", {"item_seqs": ["200003488"]}, token_a)
preg = [c for c in b.get("cautions", []) if c["type"] == "PREGNANCY"] if isinstance(b, dict) else []
check("임신 중인데 기준 확인 중 → 확인 필요(CHECK)", lambda: preg and preg[0]["applies"] == "CHECK", preg[0]["applies"] if preg else None)
s, b = call("PUT", "/me/profile", {"pregnancy": "UNKNOWN"}, token_a)
check("임신 여부 모름으로 되돌리기", lambda: s == 200 and b["pregnancy"] == "UNKNOWN", s)
s, b = call("PUT", "/me/profile", {"pregnancy": "MAYBE"}, token_a)
check("정해진 값이 아니면 422", lambda: s == 422, s)
# 누구의 약인지 + 성별 (고연수 10/11)
s, b = call("GET", "/me/profile", token=token_a)
check("프로필에 subject·sex가 있고 기본값은 UNKNOWN",
      lambda: s == 200 and b["subject"] == "UNKNOWN" and b["sex"] == "UNKNOWN", (s, b))
s, b = call("PUT", "/me/profile", {"subject": "OTHER", "sex": "MALE"}, token_a)
check("subject·sex 저장", lambda: s == 200 and b["subject"] == "OTHER" and b["sex"] == "MALE", (s, b))
s, b = call("PUT", "/me/profile", {"pregnancy": "PREGNANT"}, token_a)
check("성별만 바꿔도 임신 여부는 남아 있음", lambda: s == 200 and b["sex"] == "MALE", (s, b))
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)
preg = [c for c in b.get("cautions", []) if c["type"] == "PREGNANCY"] if isinstance(b, dict) else []
ok = lambda: preg and preg[0]["applies"] == "CHECK" and "다시 확인" in (preg[0]["applies_note"] or "")
check("남성 + 임신 중 저장 → 입력 충돌이라 CHECK (NO로 단정 안 함)", ok, (preg[0]["applies"], preg[0]["applies_note"]) if preg else None)
s, b = call("GET", "/me/profile", token=token_a)
check("충돌이어도 저장된 임신 여부는 그대로 PREGNANT", lambda: b.get("pregnancy") == "PREGNANT", b.get("pregnancy"))
s, b = call("PUT", "/me/profile", {"pregnancy": "NOT_PREGNANT"}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)
preg = [c for c in b.get("cautions", []) if c["type"] == "PREGNANCY"] if isinstance(b, dict) else []
ok = lambda: preg and preg[0]["applies"] == "NO" and "남성" in (preg[0]["applies_note"] or "")
check("남성 + 임신 아님 → 해당 안 됨(NO)", ok, (preg[0]["applies"], preg[0]["applies_note"]) if preg else None)
s, b = call("PUT", "/me/profile", {"pregnancy": "PREGNANT"}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)
check("DUR 응답에 sex·subject가 같이 온다",
      lambda: b.get("sex") == "MALE" and b.get("subject") == "OTHER", (b.get("sex"), b.get("subject")))
check("판정 문구가 본인 기준 표현('하셨어요')을 쓰지 않는다",
      lambda: not any("하셨" in (c.get("applies_note") or "") for c in b.get("cautions", [])),
      [c.get("applies_note") for c in b.get("cautions", [])])
check("남성에게는 임신 여부를 입력하라고 하지 않는다",
      lambda: not any("임신 여부" in n for n in b.get("notes", [])), b.get("notes"))
s, b = call("PUT", "/me/profile", {"sex": "FEMALE"}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": ["199000939"]}, token_a)
preg = [c for c in b.get("cautions", []) if c["type"] == "PREGNANCY"] if isinstance(b, dict) else []
check("여성으로 되돌리면 다시 해당됨(YES)", lambda: preg and preg[0]["applies"] == "YES", preg[0]["applies"] if preg else None)
s, b = call("PUT", "/me/profile", {"sex": "OTHER"}, token_a)
check("성별이 정해진 값이 아니면 422", lambda: s == 422, s)
s, b = call("PUT", "/me/profile", {"subject": "FAMILY"}, token_a)
check("subject가 정해진 값이 아니면 422", lambda: s == 422, s)
call("PUT", "/me/profile", {"subject": "UNKNOWN", "sex": "UNKNOWN", "pregnancy": "PREGNANT"}, token_a)
# 분할주의 (김서현 10/16) — 품목코드 연결 참고정보, 판정 아님
print("[12-3] 분할주의")
s, b = call("POST", "/dur/check", {"item_seqs": ["197600483"]}, token_a)  # 신일비사코딜정, 장용성당의정
sp = [c for c in b.get("cautions", []) if c["type"] == "SPLIT"] if isinstance(b, dict) else []
check("비사코딜정 → 분할주의 1건", lambda: len(sp) == 1, [c["type"] for c in b.get("cautions", [])] if isinstance(b, dict) else b)
check("분할주의는 분할불가 + 제형으로 표시", lambda: sp and sp[0]["detail"].startswith("분할주의 · 분할불가") and "장용성" in sp[0]["detail"], sp[0]["detail"] if sp else None)
check("품목코드 연결 → status CONFIRMED, info에 '연결 기준: 품목코드 일치'", lambda: sp and sp[0]["status"] == "CONFIRMED" and sp[0]["info"].get("연결 기준") == "품목코드 일치", sp[0]["info"] if sp else None)
check("분할주의 applies는 항상 CHECK (사용자별 판정 아님)", lambda: sp and sp[0]["applies"] == "CHECK", sp[0]["applies"] if sp else None)
check("변경일은 info에, notice_date는 null (고시일 아님)", lambda: sp and sp[0]["notice_date"] is None and sp[0]["info"].get("변경일") == "2021-04-22", (sp[0]["notice_date"], sp[0]["info"].get("변경일")) if sp else None)
check("분할주의가 있어도 verdict는 그대로", lambda: isinstance(b, dict) and b["drugs"][0]["verdict"] in ("NO_KNOWN_ISSUE", "UNDETERMINED"), b["drugs"][0]["verdict"] if isinstance(b, dict) else None)
check("findings에는 안 들어감", lambda: isinstance(b, dict) and not any(f["type"] == "SPLIT" for f in b["findings"]))
check("'분할 가능'이라는 말이 응답 어디에도 없음", lambda: "분할 가능" not in json.dumps(b, ensure_ascii=False) and "분할가능" not in json.dumps(b, ensure_ascii=False))
check("안내에 '정보가 없는 약도 쪼개도 된다는 뜻은 아니에요'", lambda: isinstance(b, dict) and any("쪼개도 된다는 뜻은 아니" in n for n in b.get("notes", [])), b.get("notes") if isinstance(b, dict) else None)
s, b = call("POST", "/dur/check", {"item_seqs": ["202106092"]}, token_a)  # 타이레놀정500
check("분할주의 없는 약엔 SPLIT이 안 붙음", lambda: isinstance(b, dict) and not any(c["type"] == "SPLIT" for c in b["cautions"]))
# 복용 시작일 → 투여기간주의 판정
s, b = call("POST", "/me/drugs", {"item_seq": "197600483"}, token_a)  # 비사코딜, 기준 7일
dur_drug = b.get("id") if isinstance(b, dict) else None
check("복용 시작일을 안 보내면 null", lambda: s == 201 and b["started_on"] is None and b["ended_on"] is None, (s, b))
s, b = call("POST", "/dur/check", {"item_seqs": ["197600483"]}, token_a)
dcs = [c for c in b.get("cautions", []) if c["type"] == "DURATION"] if isinstance(b, dict) else []
check("시작일 없으면 판정 UNKNOWN", lambda: dcs and dcs[0]["applies"] == "UNKNOWN", dcs[0]["applies"] if dcs else None)
long_ago = (dt.date.today() - dt.timedelta(days=40)).isoformat()
s, b = call("PATCH", f"/me/drugs/{dur_drug}", {"started_on": long_ago}, token_a)
check("복용 시작일 저장", lambda: s == 200 and b["started_on"] == long_ago, (s, b))
s, b = call("POST", "/dur/check", {"item_seqs": ["197600483"]}, token_a)
dcs = [c for c in b.get("cautions", []) if c["type"] == "DURATION"] if isinstance(b, dict) else []
ok = lambda: dcs and any(c["applies"] == "CHECK" and "멈췄다면" in (c["applies_note"] or "") for c in dcs)
check("41일 복용인데 종료일을 모르면 확정하지 않음(CHECK)", ok, [(c["applies"], c["applies_note"]) for c in dcs])
s, b = call("PATCH", f"/me/drugs/{dur_drug}", {"ended_on": dt.date.today().isoformat()}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": ["197600483"]}, token_a)
dcs = [c for c in b.get("cautions", []) if c["type"] == "DURATION"] if isinstance(b, dict) else []
ok = lambda: dcs and any(c["applies"] == "CHECK" and "경과기간" in (c["applies_note"] or "") and "넘었어요" in (c["applies_note"] or "") for c in dcs)
check("종료일이 있어도 초과는 CHECK (연속 복용 미확인, YES 아님)", ok, [(c["applies"], c["applies_note"]) for c in dcs])
check("투여기간 판정에 YES가 없다", lambda: not any(c["applies"] == "YES" for c in dcs), [c["applies"] for c in dcs])
call("PATCH", f"/me/drugs/{dur_drug}", {"ended_on": None}, token_a)
recent = (dt.date.today() - dt.timedelta(days=2)).isoformat()
s, b = call("PATCH", f"/me/drugs/{dur_drug}", {"started_on": recent}, token_a)
s, b = call("POST", "/dur/check", {"item_seqs": ["197600483"]}, token_a)
dcs = [c for c in b.get("cautions", []) if c["type"] == "DURATION"] if isinstance(b, dict) else []
check("3일 복용 → 기준 안(NO)", lambda: dcs and any(c["applies"] == "NO" for c in dcs), [c["applies"] for c in dcs])
s, b = call("PATCH", f"/me/drugs/{dur_drug}", {"ended_on": (dt.date.today() - dt.timedelta(days=5)).isoformat()}, token_a)
check("종료일이 시작일보다 빠르면 422", lambda: s == 422, s)
# 기간은 약마다 따로 저장된다 (김서현 검수표 U06)
s, b = call("POST", "/me/drugs", {"item_seq": "199302061"}, token_a)  # 듀오락스정, 역시 기준 7일
dur_drug2 = b.get("id") if isinstance(b, dict) else None
far = (dt.date.today() - dt.timedelta(days=40)).isoformat()
near = (dt.date.today() - dt.timedelta(days=2)).isoformat()
call("PATCH", f"/me/drugs/{dur_drug}", {"started_on": far, "ended_on": None}, token_a)
s, b = call("PATCH", f"/me/drugs/{dur_drug2}", {"started_on": near, "ended_on": None}, token_a)
check("두 번째 약에 다른 기간 저장", lambda: s == 200 and b["started_on"] == near, (s, b))
s, b = call("GET", "/me/drugs", token=token_a)
mine = {x["id"]: x for x in b} if isinstance(b, list) else {}
ok = lambda: mine.get(dur_drug, {}).get("started_on") == far and mine.get(dur_drug2, {}).get("started_on") == near
check("약마다 기간이 따로 남는다 (서로 덮어쓰지 않음)", ok,
      [(mine.get(dur_drug, {}).get("started_on"), mine.get(dur_drug2, {}).get("started_on"))])
s, b = call("POST", "/dur/check", {"item_seqs": ["197600483", "199302061"]}, token_a)
d1 = [c for c in b.get("cautions", []) if c["type"] == "DURATION" and "197600483" in c["item_seqs"]] if isinstance(b, dict) else []
d2 = [c for c in b.get("cautions", []) if c["type"] == "DURATION" and "199302061" in c["item_seqs"]] if isinstance(b, dict) else []
ok = lambda: d1 and d2 and d1[0]["applies"] == "CHECK" and d2[0]["applies"] == "NO"
check("판정도 약마다 자기 기간으로 따로 난다", ok,
      [(d1[0]["applies"] if d1 else None), (d2[0]["applies"] if d2 else None)])
call("DELETE", f"/me/drugs/{dur_drug2}", token=token_a)
s, b = call("PATCH", f"/me/drugs/{dur_drug}", {"started_on": None, "ended_on": None}, token_a)
check("복용 기간을 null로 지울 수 있음", lambda: s == 200 and b["started_on"] is None, (s, b))
call("DELETE", f"/me/drugs/{dur_drug}", token=token_a)

# ---------- 13. 자동 복용 시간표 제안 ----------
print("[13] 자동 시간표 제안")
s, b = call("POST", "/me/schedules/suggest")
check("토큰 없이 제안 → 401", lambda: s == 401, s)
s, b = call("POST", "/me/drugs", {"item_seq": "202106092"}, token_a)  # 타이레놀정500, 1일 3~4회
sug_drug = b.get("id") if isinstance(b, dict) else None
s, b = call("POST", "/me/schedules/suggest", None, token_a)
ok = lambda: (
    s == 200 and len(b["suggestions"]) == 1
    and b["suggestions"][0]["user_drug_id"] == sug_drug
    and b["suggestions"][0]["confidence"] in ("HIGH", "CONFIRM", "NONE")
    and len(b["suggestions"][0]["slots"]) == (b["suggestions"][0]["times_per_day"] or 0)
)
check("내 약 전체 제안 (바디 없음)", ok, (s, b.get("suggestions") if isinstance(b, dict) else b))
first = b["suggestions"][0] if isinstance(b, dict) and b.get("suggestions") else {}
check("타이레놀 1일 3~4회 → 3회로 제안 + 확인 요청", lambda: first.get("times_per_day") == 3 and first.get("confidence") == "CONFIRM" and first.get("warnings"), (first.get("times_per_day"), first.get("confidence")))
check("시각은 모두 HH:mm, 식사 관계는 정해진 값", lambda: all(len(x["time"]) == 5 and x["meal_relation"] in ("BEFORE", "AFTER", "EMPTY", "NONE") for x in first.get("slots", [])), first.get("slots"))
check("근거 문장과 안내가 함께 온다", lambda: isinstance(first.get("basis"), str) and len(b["notes"]) >= 2, (first.get("basis"), b.get("notes")))
s, b = call("POST", "/me/schedules/suggest", {"base_times": {"breakfast": "07:00", "lunch": "12:00", "dinner": "19:00"}}, token_a)
ok = lambda: s == 200 and b["base_times"]["breakfast"] == "07:00" and b["suggestions"][0]["slots"][0]["time"] == "07:00"
check("기준 시각을 바꾸면 제안 시각도 바뀐다", ok, (s, b.get("base_times") if isinstance(b, dict) else b))
s, b = call("POST", "/me/schedules/suggest", {"base_times": {"breakfast": "7:00"}}, token_a)
check("시각 형식 오류(7:00) → 422", lambda: s == 422, s)
s, b = call("POST", "/me/schedules/suggest", {"base_times": {"brunch": "10:00"}}, token_a)
check("없는 기준 시각 이름 → 422", lambda: s == 422, s)
s, b = call("POST", "/me/schedules/suggest", {"user_drug_ids": [999999]}, token_a)
check("남의(없는) 약 번호 → 빈 제안", lambda: s == 200 and b["suggestions"] == [], (s, b))
s, b = call("POST", "/me/schedules/suggest", None, token_b)
check("다른 사용자는 내 제안이 안 보임", lambda: s == 200 and b["suggestions"] == [], (s, b))
# 나이별 용법이 있으면 나이에 맞는지 확인을 요청한다 (손채은 10/7 제안)
call("PUT", "/me/profile", {"birth_year": None, "birth_date": None}, token_a)
s, b = call("POST", "/me/schedules/suggest", None, token_a)
check("나이를 모르면 age_known=false", lambda: s == 200 and b["age_known"] is False, s)
call("POST", "/me/drugs", {"item_seq": "195700020"}, token_a)  # 활명수, 나이별 용량
s, b = call("POST", "/me/schedules/suggest", None, token_a)
hwal = [x for x in b.get("suggestions", []) if x["item_seq"] == "195700020"] if isinstance(b, dict) else []
check("나이 모름 + 나이별 용법 → 생년월일 안내", lambda: hwal and any("생년월일" in w for w in hwal[0]["warnings"]), hwal[0]["warnings"] if hwal else None)
call("PUT", "/me/profile", {"birth_date": "1990-05-05"}, token_a)
s, b = call("POST", "/me/schedules/suggest", None, token_a)
hwal = [x for x in b.get("suggestions", []) if x["item_seq"] == "195700020"] if isinstance(b, dict) else []
ok = lambda: s == 200 and b["age_known"] is True and hwal and hwal[0]["confidence"] == "CONFIRM" and any("본인 나이" in w for w in hwal[0]["warnings"])
check("나이 알아도 구간이 여러 개면 확인 필요", ok, (s, hwal[0]["warnings"] if hwal else None))
s, b = call("GET", "/me/drugs", token=token_a)
hwal_id = [x["id"] for x in b if x["item_seq"] == "195700020"][0] if isinstance(b, list) else None
call("DELETE", f"/me/drugs/{hwal_id}", token=token_a)
# '성인' 기준만 적힌 용법도 나이가 안 맞으면 확인 필요 (손채은 10/9 검수)
call("POST", "/me/drugs", {"item_seq": "197000037"}, token_a)  # 아로나민골드정, 성인 1일 2회
s, b = call("GET", "/me/drugs", token=token_a)
adult_id = [x["id"] for x in b if x["item_seq"] == "197000037"][0] if isinstance(b, list) else None
# 숫자 없이 '성인'이라고만 적힌 용법은 나이를 알든 모르든 적용 가능한지 알 수 없다 (김서현 10/9)
for label, profile in [("성인", {"birth_date": "1990-05-05"}),
                       (f"{int(time.strftime('%Y')) - 7}년생", {"birth_date": f"{int(time.strftime('%Y')) - 7}-01-01"}),
                       ("나이 모름", {"birth_year": None, "birth_date": None})]:
    call("PUT", "/me/profile", profile, token_a)
    s, b = call("POST", "/me/schedules/suggest", {"user_drug_ids": [adult_id]}, token_a)
    one = b["suggestions"][0] if isinstance(b, dict) and b.get("suggestions") else {}
    ok = lambda: s == 200 and one.get("confidence") == "CONFIRM" and any("성인 기준 용법" in w for w in one.get("warnings", []))
    check(f"성인 기준 용법 + 사용자 {label} → 확인 필요", ok, (s, one.get("confidence"), one.get("warnings")))
call("DELETE", f"/me/drugs/{adult_id}", token=token_a)
call("PUT", "/me/profile", {"birth_year": None, "birth_date": None}, token_a)

# 자동 제안 중복 저장 막기 (손채은 10/12)
# 서버 코드가 김서현 검토 전용 표를 건드리지 않는지 (10/16). PC 복원 방식에서는 pillflow_app이 소유자라 DB 권한으로 막히지 않아 코드로 지킨다.
print("[0-1] 검토 전용 표 미참조")
import glob, os
REVIEW_ONLY = ("drug_dose_condition_candidates", "drug_combo_condition_candidates", "drug_combo_condition_components",
               "drug_composition_review_groups", "drug_composition_review_components", "drug_composition_review_annotations",
               "dur_split_products",  # 분할주의 원문 표. 서버는 v_app_split_warnings 뷰만 읽는다 (김서현 10/16)
               "data_collection_runs", "data_source_artifacts", "data_import_verifications",  # 수집 이력 표 (10/18)
               "data_source_inventory_snapshots", "data_source_inventory_files")  # 허가·주성분 수집 근거 이력 (10/19)
here = os.path.dirname(os.path.abspath(__file__))
hits = []
for f in glob.glob(os.path.join(here, "*.py")):
    if os.path.basename(f) == "check_api.py":
        continue
    src = open(f, encoding="utf-8").read()
    hits += [(os.path.basename(f), t) for t in REVIEW_ONLY if t in src]
check("서버 코드가 제한 표 12개(검토 6·분할 원문 1·수집 이력 5)를 참조하지 않는다", lambda: not hits, hits)
print("[13-1] 제안 중복 저장 막기")
s, b = call("POST", "/me/schedules/suggest", {"user_drug_ids": [sug_drug]}, token_a)
one = b["suggestions"][0] if isinstance(b, dict) and b.get("suggestions") else {}
slots = one.get("slots") or []
check("저장 전에는 모든 제안이 saved=false", lambda: slots and all(x["saved"] is False and x["schedule_id"] is None for x in slots), slots)
first = slots[0] if slots else {"time": "08:00", "meal_relation": "NONE"}
s, b = call("POST", "/me/schedules", {"user_drug_id": sug_drug, "time": first["time"], "meal_relation": first["meal_relation"]}, token_a)
made = b.get("id") if isinstance(b, dict) else None
check("제안 한 개 저장 → 201", lambda: s == 201, (s, b))
s, b = call("POST", "/me/schedules", {"user_drug_id": sug_drug, "time": first["time"], "meal_relation": first["meal_relation"]}, token_a)
check("같은 약·같은 시각 다시 저장 → 409 DUPLICATE", lambda: s == 409 and b.get("code") == "DUPLICATE", (s, b))
s, b = call("POST", "/me/schedules/suggest", {"user_drug_ids": [sug_drug]}, token_a)
slots = b["suggestions"][0]["slots"] if isinstance(b, dict) and b.get("suggestions") else []
hit = [x for x in slots if x["time"] == first["time"]]
check("저장한 시각은 saved=true + schedule_id", lambda: hit and hit[0]["saved"] and hit[0]["schedule_id"] == made, hit)
check("저장 안 한 시각은 saved=false 유지", lambda: all(x["saved"] is False for x in slots if x["time"] != first["time"]), slots)
s, b = call("POST", "/me/schedules", {"user_drug_id": sug_drug, "time": "23:30", "meal_relation": "NONE"}, token_a)
spare = b.get("id") if isinstance(b, dict) else None
s, b = call("PATCH", f"/me/schedules/{spare}", {"time": first["time"]}, token_a)
check("이미 있는 시각으로 옮기면 → 409 DUPLICATE", lambda: s == 409 and b.get("code") == "DUPLICATE", (s, b))
s, b = call("PATCH", f"/me/schedules/{spare}", {"time": "23:30"}, token_a)
check("같은 시각 그대로 두는 수정은 막지 않음", lambda: s == 200, (s, b))
call("DELETE", f"/me/schedules/{spare}", token=token_a)
s, b = call("DELETE", f"/me/schedules/{made}", token=token_a)
check("시간표를 지우면 다시 saved=false", lambda: s == 204, s)
s, b = call("POST", "/me/schedules/suggest", {"user_drug_ids": [sug_drug]}, token_a)
slots = b["suggestions"][0]["slots"] if isinstance(b, dict) and b.get("suggestions") else []
check("삭제 후 제안은 모두 saved=false", lambda: slots and all(x["saved"] is False for x in slots), slots)

s, b = call("DELETE", f"/me/drugs/{sug_drug}", token=token_a)
check("제안 점검용 약 정리 → 204", lambda: s == 204, s)

print(f"\n결과: 통과 {passed}개, 실패 {failed}개")
sys.exit(1 if failed else 0)
