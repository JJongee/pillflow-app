# 필플로우 서버 (FastAPI + PostgreSQL)

## 준비물
- Python 3.12
- PostgreSQL 16 (설치할 때 정한 postgres 비밀번호 기억)
- 김서현 DB 백업 (최신: `pillflow_20261005_214208.dump`, 임부금기·용량주의 포함)과 복원 안내서 (깃에 없음, 팀 카톡에서 받기)

## 처음 한 번만 (Windows PowerShell)
1. **DB 복원**: 김서현 복원 안내서대로 `pillflow_app` 계정과 `pillflow` DB를 만들고 복원합니다.
   안내서의 표 건수가 같은지 꼭 확인합니다.
2. **라이브러리 설치**: 저장소를 받은 뒤 `backend` 폴더에서 실행합니다.
   ```
   py -3.12 -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   ```
3. **`.env` 만들기**: `.env.example`을 복사해 `.env`를 만들고 `비밀번호` 자리에 `pillflow_app` 비밀번호를 넣습니다.
   비밀번호에 `@`가 있으면 `%40`으로 바꿔 씁니다.

## 실행 (켤 때마다, backend 폴더에서)
```
.\.venv\Scripts\Activate.ps1
python -m uvicorn main:app --reload
```
- `Activate.ps1`이 실행 정책 오류로 막히면 한 번만 입력: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
- 서버 코드가 바뀌면 `git pull` 후 그대로 다시 켜면 됩니다. (`requirements.txt`가 바뀌었으면 `python -m pip install -r requirements.txt` 한 번 더)
- API 문서: http://127.0.0.1:8000/docs
- 첫 실행 때 서버용 표(users, user_drugs, schedules, intake_logs)가 자동으로 만들어지고 데모 계정 `demo@pillflow.app` / `1234`가 생깁니다. 김서현 표는 건드리지 않습니다.
- 앱(에뮬레이터)은 `flutter run --dart-define=USE_MOCK=false`로 이 서버에 붙습니다.
- `drugs 표를 찾을 수 없어요` 오류가 나면 DB 복원이 안 됐거나 `.env`의 DB 이름이 다른 것입니다.

## API (api_contract v0.2)
- 인증: `POST /api/v1/auth/signup`, `POST /api/v1/auth/login`
- 약: `GET /api/v1/drugs?q=`, `GET /api/v1/drugs/{item_seq}`
- 내 약: `GET·POST /api/v1/me/drugs`, `PATCH·DELETE /api/v1/me/drugs/{id}`
- 시간표: `GET·POST /api/v1/me/schedules`, `PATCH·DELETE /api/v1/me/schedules/{id}`
- 복용 기록: `GET /api/v1/me/intakes?date=`, `PUT /api/v1/me/intakes`
- 프로필: `GET·PUT /api/v1/me/profile`
- DUR: `POST /api/v1/dur/check` (body `{"item_seqs": [...]}`, 빼면 내 약 전체)
- 자동 시간표 제안: `POST /api/v1/me/schedules/suggest` (바디 전부 생략 가능, 저장은 하지 않음)

## DUR 판별 기준
- **병용금기 + 연령금기**를 판별합니다.
- **임부금기·용량주의**는 임신 여부·복용량 입력이 아직 없어서 판정(`verdict`)에 넣지 않고, 응답의 `cautions`에 약별 참고 정보로 줍니다. 기준 확인 중(`PENDING`)인 기록도 빼지 않습니다.
- 연령금기는 프로필의 태어난 해로 판단합니다. 태어난 해가 없으면 판단하지 않고 `age_unknown: true`를 돌려줍니다.
- 태어난 해만 알기 때문에 생일에 따라 해당 여부가 갈리는 경우도 금기로 경고하고, `condition_note`에 그 사실을 적습니다.
- 연령금기 표가 없는 예전 백업에서는 병용금기만 판별하고, 임부·용량 뷰가 없으면 `cautions`는 빈 목록입니다.
- `CONTRAINDICATED`: 함께 고른 약 사이에 병용금기 기록이 있음 → 시간 분리가 아니라 의사·약사 상담 안내
- `NO_KNOWN_ISSUE`: DUR 수집은 끝났지만 이번 조합에 기록 없음 → **"안전"으로 표시하지 않음**
- `UNDETERMINED`: DUR 수집 기록이 없는 약 → 판정 불가
- A-B, B-A 양방향으로 조회하므로 순서를 바꿔도 결과가 같습니다. 금기사유가 여러 개면 모두 반환합니다.
- 두 약이 모두 검색 목록에 있는 금기쌍은 15쌍입니다. (예: 199300273 멕시롱액 ↔ 201706199 코메키나캡슐)

## 자동 시간표 제안 기준
- 약의 용법 문장(e약은요 `use_method`)을 읽어 하루 복용 시각을 **제안만** 합니다. 저장은 사용자가 확인한 뒤 앱이 기존 `POST /me/schedules`로 합니다.
- 기준 시각 5개(기상 07:00, 아침 08:00, 점심 12:30, 저녁 18:30, 취침 22:30)에 배치하고, 식전은 30분 앞, 식후는 30분 뒤, 공복·식간은 2시간 뒤로 옮깁니다. 요청의 `base_times`로 바꿀 수 있습니다.
- 횟수가 범위면(1일 3~4회) 작은 값으로 제안하고 `confidence`를 `CONFIRM`으로 돌려줍니다.
- **용량(몇 정·몇 mL)은 제안하지 않습니다.** 나이별 용량이 절반 가까워 잘못 고를 위험이 큽니다.
- 먹는 약이 아니거나, 필요할 때만 먹는 약이거나, 횟수를 읽지 못한 약은 짐작하지 않고 `confidence: NONE`으로 돌려줍니다.
- 병용금기가 있어도 시간을 나눠서 해결하지 않고 `dur_findings`에 경고만 붙입니다.
- 먹는 약 3,520건 중 3,055건(86%)에 제안이 나옵니다. (바로 쓸 만함 2,393건)

## 참고
- 에러 응답은 `{"detail": 메시지, "code": NOT_FOUND 등}` 형식입니다.
- DB 구조는 김서현 `pillflow_db_erd_spec.docx`를 따릅니다.
