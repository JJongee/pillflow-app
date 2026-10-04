# API 계약 v0.2 → 실제 서버 차이 (v0.3 제안)

> 작성: 주연우(서버) · 2026-10-05 · 기준: `docs/api_contract.md` v0.2, 서버 `backend/` (점검 45개 통과)
> 고연수 님과 합의되면 `docs/api_contract.md`를 v0.3으로 고칩니다. 그 전까지는 이 문서가 서버의 실제 동작입니다.

**요약**: 경로·필드 이름·코드값은 v0.2와 같습니다. 바뀐 건 아래 표의 항목뿐이고, 앱이 꼭 고쳐야 하는 건 없습니다.
다만 **422 응답의 `detail`이 문자열이 아니라 목록**이라, 지금 앱은 이때 "요청을 처리하지 못했어요"로만 보입니다(아래 2번).

## 1. 추가된 것

| API | 내용 |
|---|---|
| `POST /auth/signup` | 바디 `{"email", "password"}` → `201 {"id", "email"}`. 이메일은 소문자로 저장. 같은 이메일 `409 DUPLICATE`, 형식 오류·비밀번호 4자 미만 `422` |
| `GET /auth/me` | 토큰 확인용. `{"id", "email"}` |
| DUR 응답 `notes` | 안내 문구 목록(문자열 2개). 앱은 무시해도 됨 |

## 2. 에러 `code` 값

| 상태 | `code` | 언제 |
|---|---|---|
| 401 | `UNAUTHORIZED` | 토큰 없음·만료·가짜, 로그인 실패 |
| 404 | `NOT_FOUND` | 없는 약, **남의 데이터**(403 대신 404로 존재 자체를 숨김) |
| 409 | `DUPLICATE` | 같은 약 중복 등록, 같은 이메일 가입 |
| 422 | `VALIDATION_ERROR` | 입력 형식 오류. **`detail`은 FastAPI 기본 목록**(어느 칸이 틀렸는지 `loc`, `msg`) |

앱 제안: `code == "VALIDATION_ERROR"`면 "입력값을 확인해 주세요."로 보여 주면 됩니다.

## 3. 동작을 정한 것 (v0.2에 안 적혀 있던 부분)

| 항목 | 서버 동작 |
|---|---|
| 인증 | JSON `{"email","password"}` 방식 확정(form 아님). 토큰 24시간 |
| 약 정보 | 김서현 DB(`drugs`, `drug_images`)에서 읽음. 날짜는 `2026.6.29` → `2026-06-29`로 정리 |
| `PATCH /me/schedules/{id}` | 보낸 칸만 바뀜. `time`, `meal_relation`에 `null`을 보내면 무시, `dose_text`는 `null`로 지울 수 있음 |
| `PUT /me/intakes` | `status`에 `PENDING`을 보내면 그 기록을 지움(체크 취소). 응답은 `IntakeRecord` 하나 |
| `/me/profile` | `birth_year`는 1900~2100 또는 `null` |
| 시간 형식 | `HH:mm` 두 자리만 (`8:30`은 422) |

## 4. `POST /dur/check`

| 항목 | v0.2 | 실제 서버 |
|---|---|---|
| 판별 종류 | 병용금기 + 연령금기 | **병용금기만**. `AGE` 결과는 아직 없음(연령금기 데이터 없음) |
| 인증 | 표시 없음 | 필요(Bearer) |
| `item_seqs` | 생략하면 내 약 전체 | 같음. `{}` 또는 바디 없음 → 내 약 전체. 1~50개, `[]`는 422. 중복은 한 번만 |
| 약 번호 | `EDI-` 접두어 검토 | **필요 없음**. DUR API가 우리와 같은 `item_seq`를 씀 |
| `drugs[].item_name` | 문자열 | 항상 문자열. 목록에 없는 번호는 `"등록되지 않은 약 (번호)"` |
| `drugs` 순서 | — | 보낸 순서 그대로 |
| `findings[].item_seqs` | — | 작은 번호가 앞. 넣는 순서를 바꿔도 `findings`는 똑같음 |
| `ingredients` | 영문 소문자 예시 | 한글 성분명 (예: `"돔페리돈"`) |
| `notice_no` | 고시번호 | **항상 `null`** (DUR API에 없음) |
| `notice_date` | `YYYY-MM-DD` | 같음 (고시일자) |
| `condition_note` | 병용금기 CSV `비고` | DUR API `REMARK`, 비어 있으면 `null` |
| 금기사유가 여러 개 | — | 사유마다 `findings` 한 건씩 |
| `data_version` | `"DUR 게시 2609"` | `"DUR API 수집 2026-10-04"` |
| `age_unknown` | 나이 없으면 true | 같음 (지금은 판별에 쓰지 않음) |

판정 기준
- `CONTRAINDICATED`: 함께 보낸 약 사이에 병용금기 기록이 있음
- `NO_KNOWN_ISSUE`: 그 약의 DUR 수집은 끝났지만 이번 조합에 기록 없음 → **"안전"으로 표시하지 않음**
- `UNDETERMINED`: DUR 수집 기록이 없는 약 → 판정 불가

데이터 범위: 두 약이 모두 검색 목록(4,741개)에 있는 금기쌍은 15쌍입니다. 시연 예: `199300273` 멕시롱액 ↔ `201706199` 코메키나캡슐.

## 5. v0.2 "서버 쪽에 확인하고 싶은 것" 답

1. 약 식별자: DUR API가 `item_seq`(품목기준코드)를 그대로 써서 통일 문제 없음. 보험코드 연결표(`drug_code_mappings`)는 서현 DB에 있으나 지금 판별에는 안 씀.
2. 판별 단위: 성분코드 쌍이 아니라 **약품(품목) 쌍**으로 조회. 성분명은 결과에 정보로만 넣음.
3. 인증: 완료. JSON 방식, `POST /auth/login` → `{"access_token", "token_type": "bearer"}`.
