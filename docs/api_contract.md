# 필플로우 API 요청·응답 (v0.3)

> v0.2 작성: 고연수(앱) · v0.3 정리: 주연우(서버) · 2026-10-11
> v0.3은 **지금 돌아가는 서버의 실제 동작**입니다. 10/11 고연수 합의로 `backend/API_CHANGES.md` 내용을 여기에 반영했습니다.
> 앱의 `lib/data/api_repository.dart`와 서버 `backend/`가 이 문서를 따릅니다. 바뀌면 셋 다 고칩니다.
> 서버 점검은 `backend/check_api.py` 146개로 확인합니다.

## 공통 규칙

| 항목 | 내용 |
|---|---|
| Base URL | `http://<개발PC IP>:8000/api/v1` (에뮬레이터는 `http://10.0.2.2:8000/api/v1`) |
| 필드 이름 | `snake_case` |
| 날짜 | `YYYY-MM-DD` 문자열. 원본이 `20210129`·`2024.05.09`로 섞여 있어 **서버에서 정규화** |
| 시각 | `HH:mm` 두 자리 (`08:30`. `8:30`은 422) |
| 인증 | `Authorization: Bearer <token>`. 토큰 24시간 |
| 빈 값 | 없는 필드는 `null` (빈 문자열 `""` 대신) |
| 에러 | `{ "detail": ..., "code": "NOT_FOUND" }` + HTTP 상태코드 |
| 목록 | `{ "items": [...], "page": 1, "size": 20, "total": 123 }` |

### 에러 `code`

| 상태 | `code` | 언제 |
|---|---|---|
| 401 | `UNAUTHORIZED` | 토큰 없음·만료·가짜, 로그인 실패 |
| 404 | `NOT_FOUND` | 없는 약, **남의 데이터**(403 대신 404로 존재 자체를 숨김) |
| 409 | `DUPLICATE` | 같은 약 중복 등록, 같은 이메일 가입 |
| 422 | `VALIDATION_ERROR` | 입력 형식 오류 |

- **422일 때만 `detail`이 문자열이 아니라 목록**입니다(FastAPI 기본, 어느 칸이 틀렸는지 `loc`·`msg`).
  앱은 `code == "VALIDATION_ERROR"`면 "입력값을 확인해 주세요."로 보여 주면 됩니다.

## 0. 인증

### `POST /auth/signup`
바디: `{ "email": "a@b.com", "password": "1234" }` → `201 { "id": 1, "email": "a@b.com" }`
- 이메일은 소문자로 저장. 같은 이메일 `409 DUPLICATE`, 형식 오류·비밀번호 4자 미만 `422`

### `POST /auth/login`
바디: `{ "email": "demo@pillflow.app", "password": "1234" }` (JSON. form 방식 아님)
```json
{ "access_token": "eyJhbGciOi...", "token_type": "bearer" }
```
- 실패 시 `401` → "이메일 또는 비밀번호를 확인해 주세요."
- 다른 API에서 `401` → "로그인이 만료됐어요."

### `GET /auth/me`
토큰 확인용. `{ "id": 1, "email": "a@b.com" }`

## 1. 약 검색 · 상세

### `GET /drugs?q=타이레놀&page=1&size=20`
```json
{
  "items": [
    { "item_seq": "200008591", "item_name": "바이엘아스피린정500밀리그람",
      "entp_name": "바이엘코리아(주)", "image_url": "https://...", "source": "e약은요" }
  ],
  "page": 1, "size": 20, "total": 1
}
```
- `item_seq`는 **문자열**. 검색은 띄어쓰기를 무시합니다. `q` 없으면 422, `size`는 1~100.

### `GET /drugs/{item_seq}`
```json
{
  "item_seq": "200008591",
  "item_name": "...", "entp_name": "...", "image_url": null,
  "efficacy": "...", "use_method": "...", "warning": null, "caution": "...",
  "interaction": "...", "side_effect": "...", "storage": "...",
  "open_date": "2021-01-29", "update_date": "2024-05-09", "source": "e약은요"
}
```
- 없는 번호는 `404 NOT_FOUND`. 약 정보는 김서현 DB(`drugs`, `drug_images`)에서 읽습니다.

## 2. 내 약

| 메서드 | 경로 | 바디 | 응답 |
|---|---|---|---|
| GET | `/me/drugs` | – | `[UserDrug]` |
| POST | `/me/drugs` | `{ "item_seq": "200008591", "memo": "아침에", "started_on": "2026-10-01" }` | `UserDrug` (201) |
| PATCH | `/me/drugs/{id}` | 바꿀 칸만 | `UserDrug` |
| DELETE | `/me/drugs/{id}` | – | 204 (연결된 시간표도 같이 삭제) |

```json
// UserDrug
{ "id": 12, "item_seq": "200008591", "item_name": "...", "entp_name": "...",
  "image_url": null, "memo": "아침에", "created_at": "2026-10-05",
  "started_on": "2026-10-01", "ended_on": null }
```
- 같은 약 중복 등록 시 `409 DUPLICATE`, 없는 약은 `404`.
- `started_on`·`ended_on`은 복용 시작일·종료일(10/11 추가). `YYYY-MM-DD` 또는 `null`, 둘 다 선택 입력.
  투여기간주의 판정에 씁니다. `ended_on`이 `started_on`보다 빠르면 422.

## 3. 복용 시간표 (사용자 지정)

### `GET /me/schedules`
```json
[
  { "id": 3, "user_drug_id": 12, "item_name": "...", "time": "08:30",
    "meal_relation": "AFTER", "dose_text": "1정", "dose_amount": 1, "dose_unit": "정" }
]
```
- `meal_relation`: `BEFORE`(식전) · `AFTER`(식후) · `EMPTY`(공복) · `NONE`

### `POST /me/schedules` → 201 / `PATCH /me/schedules/{id}` / `DELETE /me/schedules/{id}` → 204
바디: `{ "user_drug_id": 12, "time": "08:30", "meal_relation": "AFTER", "dose_amount": 1, "dose_unit": "정" }`

- **1회 복용량**(10/10 추가): `dose_amount`는 0 초과 1000 이하(소수점 셋째 자리까지, `0.5` 가능).
  `dose_unit`은 앱 목록과 같은 6개 — `정`·`캡슐`·`포`·`mL`·`방울`·`매`. 다른 값은 422.
  목록에 없는 단위는 앱이 '직접 입력'으로 `dose_text`에만 넣습니다. 단위를 늘리려면 앱과 `backend/schedules.py`의 `DoseUnit`을 같이 고쳐야 합니다.
  **서버는 기록만 하고 용량 초과 판정은 하지 않습니다.**
- **같은 약 + 같은 시각은 한 번만** 저장됩니다. 겹치면 `409 DUPLICATE`이고, `PATCH`로 시각을 옮겨 겹치게 하는 것도 막습니다. (10/12 추가)
- `PATCH`는 보낸 칸만 바뀝니다. `time`·`meal_relation`에 `null`을 보내면 무시하고,
  `dose_text`·`dose_amount`·`dose_unit`은 `null`로 지울 수 있습니다.

## 4. 복용 기록

### `GET /me/intakes?date=2026-10-05`
그날 시간표 전체 + 기록 상태 (기록 없으면 `PENDING`). 시각 순서로 옵니다.
```json
[
  { "schedule_id": 3, "date": "2026-10-05", "time": "08:30", "item_name": "...",
    "status": "TAKEN", "recorded_at": "2026-10-05T08:41:00" }
]
```
- `status`: `TAKEN` · `SKIPPED` · `PENDING`

### `PUT /me/intakes`
바디: `{ "schedule_id": 3, "date": "2026-10-05", "status": "TAKEN" }` → 200, `IntakeRecord` 하나
- 같은 `schedule_id` + `date`면 덮어씁니다.
- `status`에 `PENDING`을 보내면 그 기록을 지웁니다(체크 취소).

## 5. 프로필

### `GET /me/profile` · `PUT /me/profile` (보낸 칸만 바뀜)
```json
{ "birth_year": 1960, "birth_date": "1960-03-15",
  "pregnancy": "UNKNOWN", "subject": "UNKNOWN", "sex": "UNKNOWN" }
```

| 칸 | 값 | 설명 |
|---|---|---|
| `birth_year` | 1900~2100, `null` 가능 | 태어난 해만 알 때 |
| `birth_date` | `YYYY-MM-DD` (1900-01-01~오늘), `null` 가능 | 넣으면 연령금기를 달력으로 정확히 판단. 넣을 때 `birth_year`도 같이 맞춰짐 |
| `pregnancy` | `PREGNANT` · `NOT_PREGNANT` · `UNKNOWN` | 임신 여부(10/11). 민감한 정보라 선택 입력 |
| `subject` | `SELF` · `OTHER` · `UNKNOWN` | 이 프로필이 누구 약인지(10/11) |
| `sex` | `FEMALE` · `MALE` · `UNKNOWN` | 성별(10/11) |

- `subject` 기본값은 `UNKNOWN`입니다. '응답 안 함'을 '본인'으로 바꾸지 않습니다. (10/12 고연수 합의)
- 프로필은 **약 먹는 사람 한 명** 기준입니다. 가족 약을 대신 관리하는 경우를 위해 `subject`를 둡니다.
  한 계정으로 여러 명을 따로 관리하는 건 후속 과제입니다. (고연수 10/11)
- `sex`가 `MALE`이면 임부금기 `applies`를 `NO`로 내려보냅니다 ("남성으로 입력해서 해당되지 않아요").
- 나이가 아예 없으면 연령금기를 판별하지 않고 `age_unknown: true`로 응답합니다.
- 태어난 해만 바꿨는데 저장된 생년월일과 어긋나면 오래된 생년월일을 지웁니다.

## 6. DUR 판별

### `POST /dur/check`
바디: `{ "item_seqs": ["200008591"] }` — 1~50개. 생략하거나 `{}`면 내 약 전체, `[]`는 422. 중복은 한 번만.

```json
{
  "data_version": "DUR API 수집 2026-10-04",
  "checked_at": "2026-10-11",
  "age_unknown": false,
  "pregnancy": "UNKNOWN", "sex": "UNKNOWN", "subject": "UNKNOWN",
  "drugs": [
    { "item_seq": "199300273", "item_name": "멕시롱액", "verdict": "CONTRAINDICATED" }
  ],
  "findings": [
    { "type": "COMBINATION", "item_seqs": ["199300273", "201706199"],
      "ingredients": ["돔페리돈", "메퀴타진"],
      "detail": "QTc 연장 효과 증대로 심각한 위험 가능성",
      "condition_note": null, "notice_no": null, "notice_date": "2015-11-30" }
  ],
  "cautions": [],
  "notes": ["..."]
}
```

| 칸 | 내용 |
|---|---|
| `drugs` | 보낸 순서 그대로. `item_name`은 항상 문자열 (모르는 번호는 `"등록되지 않은 약 (번호)"`) |
| `findings[].type` | `COMBINATION`(병용금기) · `AGE`(연령금기) |
| `findings[].item_seqs` | 병용금기는 2개(작은 번호가 앞), 연령금기는 1개 |
| `ingredients` | 한글 성분명 |
| `notice_no` | **항상 `null`** (DUR API에 없음) |
| `notice_date` | 고시일자 `YYYY-MM-DD` |
| `condition_note` | DUR API `REMARK`. 비어 있으면 `null`. **앱에서 반드시 노출** |
| `age_unknown` | `birth_year`·`birth_date`가 둘 다 없을 때만 true |
| `pregnancy`·`sex`·`subject` | 프로필 값을 그대로 돌려줌 |
| `notes` | 안내 문구 목록. 앱은 무시해도 됨 |

- 약 번호에 `EDI-` 접두어는 필요 없습니다. DUR API가 우리와 같은 `item_seq`를 씁니다.
- 판별은 성분 쌍이 아니라 **약품(품목) 쌍**으로 합니다. 성분명은 정보로만 넣습니다.
- 금기사유가 여러 개면 사유마다 `findings` 한 건씩 나옵니다.
- 연령금기: `birth_date`가 있으면 달력으로 정확히 판단하고, 태어난 해만 있으면 생일에 따라 갈리는 경우를 금기로 보고 `condition_note`에 안내를 넣습니다.

### `verdict` 세 가지
- `CONTRAINDICATED`: 금기 근거 있음 → **시간 분리로 해결하지 않고** 전문가 상담 안내
- `NO_KNOWN_ISSUE`: DUR 수집은 끝났지만 이번 조합에 걸린 규칙 없음 → **"안전"으로 표시하지 않음**
- `UNDETERMINED`: DUR 수집 기록이 없는 약 → 판정 불가

> 검색 목록 4,741개 안에서 두 약이 모두 잡히는 금기쌍은 15쌍입니다.
> 시연 예: `199300273` 멕시롱액 ↔ `201706199` 코메키나캡슐.

## 6-1. `cautions` (참고 정보 5종)

`findings`에 넣으면 앱이 병용금기로 보여 주기 때문에 **칸을 따로 뒀습니다.** 약마다 0건 이상.

```json
{ "type": "PREGNANCY", "item_seqs": ["199000939"], "ingredients": ["성분명"],
  "status": "CONFIRMED", "grade": "2등급",
  "detail": "임부금기 2등급 · 사유",
  "info": {"등급": "2등급", "성분": "...", "금기 사유": "..."},
  "condition_note": null,
  "applies": "YES", "applies_note": "임신 중이라고 하셨어요. ...",
  "notice_date": "2014-12-30" }
```

| `type` | 뜻 | `info` 줄 |
|---|---|---|
| `PREGNANCY` | 임부금기 | 등급 · 성분 · 금기 사유 |
| `DOSE` | 용량주의 | 성분 · 1일 최대량 · 제형 |
| `ELDERLY` | 노인주의 | 성분 · 제형 |
| `DUPLICATE` | 효능군 중복주의 | 효능군 · 계열 · 성분 |
| `DURATION` | 투여기간주의 | 기간 기준 · 성분 · 제형 |

- **`info`는 화면에 줄로 보여 줄 항목입니다.** 원본에 값이 없는 칸은 아예 넣지 않으니 앱은 받은 칸만 그리면 됩니다.
- 노인주의는 DUR 원본부터 주의 내용과 비고가 비어 있습니다(앱 대상 521건 전부, 김서현 10/9 확인).
  `condition_note`에 "원본에 상세 주의내용이 제공되지 않았어요."가 들어갑니다. **빈 값을 "주의사항 없음"으로 보여 주면 안 됩니다.**

### `status`(데이터 연결 상태)와 `applies`(판정 결과)는 다른 칸입니다

| `status` | 뜻 |
|---|---|
| `CONFIRMED` | 기준 확인됨 |
| `PENDING` | 기준 확인 중 — **"괜찮음"이 아님.** `detail` 끝에도 "기준 확인 중"이 붙음 |
| `CONFLICT` | 기준이 서로 달라 등급을 정하지 못함 |

| `applies` | 뜻 | 언제 |
|---|---|---|
| `YES` | 해당됨 | 조건이 맞고 기준도 확인됨 |
| `CHECK` | 확인 필요 | 조건은 맞지만 기준이 미확정이거나 추가 조건이 필요함 |
| `NO` | 해당 안 됨 | 조건이 맞지 않음 (임신 아님, 남성, 복용 기간이 기준 안) |
| `UNKNOWN` | 입력 없음 | 임신 여부나 복용 시작일이 없어 판단할 수 없음 |

- `applies_note`에 판단 이유가 들어갑니다. 그대로 띄워도 됩니다.
  가족 약을 대신 관리하는 경우가 있어 "하셨어요" 같은 본인 기준 표현은 쓰지 않습니다 — "임신 중으로 입력되어 있어요"처럼 누구 약이든 맞는 문장입니다. (10/12 고연수 요청)
- 화면에서는 `CHECK`와 `UNKNOWN`을 둘 다 "확인 필요"로 보여 주면 됩니다.
  서버가 나눠 보내는 이유는 `UNKNOWN`일 때만 입력을 권하면 되기 때문입니다.
- **임부금기**: 성별이 `MALE`이면 `NO`. 임신 시기 조건이 붙은 기록("임신 말기에 투여시" 등)은 임신 여부만으로 확정하지 않고 `CHECK`.
- **투여기간주의**: 기준이 숫자로 확정(`simple_days`)되고 연결도 확인된 경우에만 판정하며, 기준이 여러 개면 짧은 쪽으로 봅니다.
  - 복용 시작일이 없거나 아직 시작 전 → `UNKNOWN`
  - 기간이 기준 안 → `NO`
  - 기간이 기준을 넘었는데 **종료일이 없으면** → `CHECK` (아직 먹고 있는지 알 수 없어 확정하지 않음)
  - 기간이 기준을 넘었고 종료일도 있으면 → `YES`
- **노인주의·효능군중복주의·용량주의**는 판정 기준이 없어 항상 `CHECK`입니다.
- 한 약에 같은 종류가 여러 건이면 `condition_note`에 "같은 성분의 제형·농도별 참고정보예요…"가 붙습니다.
  원본이 제형·농도별 기준을 모두 담고 있어서이고, **서버가 어느 것이 맞는지 고르지 않습니다.**
- 효능군 중복주의는 **약마다 효능군만** 알려 줍니다. 서버가 두 약을 비교해 "중복"으로 판정하지 않습니다.
- `verdict`는 병용금기·연령금기만 반영합니다. 임부금기는 `verdict`에 올리지 않기로 했습니다. (10/12 고연수 합의) 임신 중 + 해당됨일 때 앱이 경고를 강조하는 방식으로 갑니다.

## 7. 자동 시간표 제안

### `POST /me/schedules/suggest`
**서버는 제안만 하고 저장하지 않습니다.** 저장은 기존 `POST /me/schedules`로 합니다.

요청 (전부 생략 가능):
```json
{ "user_drug_ids": [12],
  "base_times": {"wake": "07:00", "breakfast": "08:00", "lunch": "12:30", "dinner": "18:30", "bedtime": "22:30"} }
```

응답:
```json
{ "suggestions": [
    { "user_drug_id": 12, "item_seq": "202106092", "item_name": "타이레놀정500밀리그람(아세트아미노펜)",
      "confidence": "CONFIRM", "times_per_day": 3,
      "slots": [{"time": "08:00", "meal_relation": "NONE"},
                {"time": "12:30", "meal_relation": "NONE"},
                {"time": "18:30", "meal_relation": "NONE"}],
      "basis": "만 12세 이상 소아 및 성인은 1회 1~2정씩, 1일 3~4회(4~6시간 마다) 필요시 복용합니다.",
      "warnings": ["횟수가 범위로 적혀 있어 작은 값(3회)으로 제안했어요. 확인해 주세요."] }],
  "base_times": {...}, "age_known": true, "dur_findings": [], "notes": ["..."] }
```

| 칸 | 값 |
|---|---|
| `confidence` | `HIGH`(그대로 쓸 만함) / `CONFIRM`(확인 필요) / `NONE`(제안 없음, `slots` 빈 목록) |
| `times_per_day` | 하루 횟수. 읽지 못하면 `null` |
| `slots[].meal_relation` | 시간표 API와 같은 `BEFORE`·`AFTER`·`EMPTY`·`NONE` |
| `slots[].saved` | 그 약·그 시각의 시간표가 이미 있으면 `true`. 앱은 '저장됨'으로 표시하고 다시 고르지 못하게 하면 됩니다 |
| `slots[].schedule_id` | `saved`가 `true`일 때 그 시간표 번호. 아니면 `null`. 시간표를 지우면 다음 제안부터 다시 `false` |
| `basis` | 근거가 된 용법 문장 한 줄 |
| `warnings` | 사용자에게 보여 줄 주의 문구. 없으면 빈 목록 |
| `age_known` | 프로필에 생년월일이나 태어난 해가 있으면 true |
| `dur_findings` | `/dur/check`의 `findings`와 같은 모양. 금기가 있어도 시간은 바꾸지 않음 |

- `base_times`는 5개 이름 중 바꿀 것만 보내면 됩니다. 이름이 틀리거나 `HH:mm`이 아니면 422.
- 내 약이 아닌 번호를 섞어 보내도 조용히 무시합니다(존재 자체를 알리지 않음).
- **먹는 약이 아니거나 투여 경로 단서가 충돌하면 `NONE`**입니다. 바르는 약·붙이는 약·점안·흡입·주사 등은 시간을 제안하지 않습니다.
- **나이별 용법**이 있으면 `HIGH` 대신 `CONFIRM`으로 내리고 `warnings`에 안내를 넣습니다.
  `성인`만 적힌 용법은 나이를 알든 모르든 항상 `CONFIRM`이고, `성인`을 숫자 나이로 바꿔 판단하지 않습니다. (김서현 10/9)
- 서버는 **몇 정·몇 mL를 먹을지 제안하지 않습니다.** `dose_text`는 비워 두니 사용자가 입력합니다.
- 앱 제안: `NONE`이면 "직접 정해 주세요" 화면으로, `CONFIRM`이면 `warnings`를 먼저 보여 주세요.

## 아직 정하지 않은 것

- 기준 시각 기본값 5개와 사용자가 바꾸는 화면 (손채은·고연수)
- 식간을 `EMPTY`로 묶을지, 값을 따로 둘지 (고연수)
- 노인주의 기준 나이, 효능군중복 적용 계열 규칙 (김서현 + 팀 합의)
- 용량 초과 자동 판정 — `max_qty_raw` 숫자화와 복합제 성분 합계가 필요해 보류 (김서현 10/11)
