# 필플로우 서버 (FastAPI + PostgreSQL)

## 준비물
- Python 3.12
- PostgreSQL 16 (설치할 때 정한 postgres 비밀번호 기억)
- 김서현 DB 백업 (최신: `pillflow_20261018_090558_228335_portable_history_reviewed.dump`, 주의 5종 + 분할주의 + 함량 검증 88품목 + 용법 조건 후보 30품목 + 수집 이력)과 복원 안내서 (깃에 없음, 팀 카톡에서 받기)
  이 백업은 **누적 전체 백업**입니다. 예전 백업을 따로 복원하거나 예전 수정용 스크립트를 돌릴 필요가 없습니다. (10/16 김서현 확인)
  제한 표 10개(검토 전용 6개 `drug_*_condition_*`·`drug_composition_review_*`, 분할주의 원문 `dur_split_products`, 수집 이력 `data_*` 3개)는 서버가 읽지 않고 앱 계정 권한도 없습니다. `check_api.py` [0-1]이 코드 참조를 점검합니다.

## 처음 한 번만 (Windows PowerShell)
1. **DB 복원** (10/16부터 바뀐 방식 — 김서현 요청): `pillflow_app`이 아니라 **관리자 계정(`postgres`)으로**, `--no-owner`만 쓰고 `--no-acl`은 **빼고** 복원합니다. 그래야 백업에 담긴 권한이 그대로 살아서 검토 전용 표가 앱 계정에 막힙니다.
   ```
   createuser -U postgres --no-superuser --no-createdb --no-createrole --pwprompt pillflow_app   (이미 있으면 생략)
   createdb -U postgres --owner=pillflow_app --encoding=UTF8 pillflow
   pg_restore -U postgres -d pillflow --no-owner --single-transaction --exit-on-error C:\Pbl\db\<백업파일>.dump
   ```
   10/18 백업부터는 서버가 읽는 기본 표 4개(`drugs`, `drug_images`, `dur_fetch_status`, `dur_interactions`)의 권한이 백업에 들어 있어 **추가 GRANT가 필요 없습니다.** (10/16 백업까지는 따로 GRANT해야 했음)
   권한 확인: `psql -U pillflow_app -d pillflow -c "SELECT count(*) FROM drugs"` 는 4741, `... FROM v_app_split_warnings` 는 185가 나오고, `... FROM dur_split_products` 는 **접근 권한 없음**이 나와야 정상입니다.
   기존 DB의 사용자 데이터(`users`, `user_drugs`, `schedules`, `intake_logs`)를 옮기려면 TODO.md의 "사용자 데이터 옮기기"를 보세요.
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
- 첫 실행 때 서버용 표(users, user_drugs, schedules, intake_logs)가 자동으로 만들어지고(이미 있으면 빠진 칸만 더해지고) 데모 계정 `demo@pillflow.app` / `1234`가 생깁니다. 김서현 표는 건드리지 않습니다.
- 앱(에뮬레이터)은 `flutter run --dart-define=USE_MOCK=false`로 이 서버에 붙습니다.
- `drugs 표를 찾을 수 없어요` 오류가 나면 DB 복원이 안 됐거나 `.env`의 DB 이름이 다른 것입니다.

## API (api_contract v0.3)
- 인증: `POST /api/v1/auth/signup`, `POST /api/v1/auth/login`
- 약: `GET /api/v1/drugs?q=`, `GET /api/v1/drugs/{item_seq}`
- 내 약: `GET·POST /api/v1/me/drugs`, `PATCH·DELETE /api/v1/me/drugs/{id}`
- 시간표: `GET·POST /api/v1/me/schedules`, `PATCH·DELETE /api/v1/me/schedules/{id}` (1회 복용량은 `dose_amount` + `dose_unit`)
- 복용 기록: `GET /api/v1/me/intakes?date=`, `PUT /api/v1/me/intakes`
- 프로필: `GET·PUT /api/v1/me/profile` (`birth_year`, `birth_date`, `pregnancy`, `subject`, `sex`)
- DUR: `POST /api/v1/dur/check` (body `{"item_seqs": [...]}`, 빼면 내 약 전체)
- 자동 시간표 제안: `POST /api/v1/me/schedules/suggest` (바디 전부 생략 가능, 저장은 하지 않음)

## DUR 판별 기준
- **병용금기 + 연령금기**를 판별합니다.
- **임부금기·용량주의·노인주의·효능군중복주의·투여기간주의·분할주의**는 응답의 `cautions`에 약별 참고 정보로 줍니다. 금기 판정(`verdict`)에는 넣지 않습니다.
  나머지 3종은 해당 여부도 판정하지 않습니다. 용량주의는 최대량이 아직 글자이고, 노인주의는 기준에 나이 값이 없으며, 효능군은 같다고 바로 중복이 아니기 때문입니다.
- 기준 확인 중(`PENDING`)인 기록도 빼지 않고 "기준 확인 중"으로 보여 줍니다. **"해당 없음"이 아닙니다.**
- 임신 여부·성별과 복용 시작일을 입력하면 **임부금기·투여기간주의가 해당되는지**를 `applies`로 알려 줍니다. 데이터 연결 상태(`status`)와는 다른 칸입니다. 조건이 불명확하면 확정하지 않고 "확인 필요"로 둡니다.
- **분할주의**(10/16 추가, `type: SPLIT`)는 서방정·장용 제형처럼 쪼개면 안 되는 약입니다. 품목코드로 연결된 참고정보라 `status`는 `CONFIRMED`이고 `info`에 "연결 기준: 품목코드 일치"가 들어갑니다. 사용자별 판정이 아니라 `applies`는 항상 `CHECK`이며 `verdict`에 넣지 않습니다. 변경일은 `info`의 "변경일"이고 `notice_date`는 null입니다. **서버는 어떤 약도 '분할 가능'이라고 말하지 않습니다.** 분할주의 정보가 없는 약도 쪼개도 된다는 뜻이 아닙니다.
  성별이 `MALE`이면 임부금기는 `NO`로 둡니다. 단 `MALE`인데 임신 중으로 저장돼 있으면 입력 충돌이라 `CHECK`로 두고 다시 확인을 받습니다.
  투여기간은 입력한 날짜로 센 경과기간이 기준을 넘어도 `YES`로 단정하지 않고 `CHECK`입니다. 중간에 끊었는지 서버가 알 수 없기 때문입니다. (10/13 김서현)
- 연령금기는 프로필의 생년월일(`birth_date`)로 판단합니다. 달력으로 계산해서 생일 당일도 정확합니다.
- 생년월일 없이 태어난 해(`birth_year`)만 있으면, 생일에 따라 해당 여부가 갈리는 경우도 금기로 경고하고 `condition_note`에 그 사실을 적습니다.
- 둘 다 없으면 연령금기를 판단하지 않고 `age_unknown: true`를 돌려줍니다.
- 예전 백업이라 뷰가 없으면 그 항목만 건너뜁니다. 연령금기 표가 없으면 병용금기만 판별합니다.
- `CONTRAINDICATED`: 함께 고른 약 사이에 병용금기 기록이 있음 → 시간 분리가 아니라 의사·약사 상담 안내
- `NO_KNOWN_ISSUE`: DUR 수집은 끝났지만 이번 조합에 기록 없음 → **"안전"으로 표시하지 않음**
- `UNDETERMINED`: DUR 수집 기록이 없는 약 → 판정 불가
- A-B, B-A 양방향으로 조회하므로 순서를 바꿔도 결과가 같습니다. 금기사유가 여러 개면 모두 반환합니다.
- 두 약이 모두 검색 목록에 있는 금기쌍은 15쌍입니다. (예: 199300273 멕시롱액 ↔ 201706199 코메키나캡슐)

## 자동 시간표 제안 기준
- 약의 용법 문장(e약은요 `use_method`)을 읽어 하루 복용 시각을 **제안만** 합니다. 저장은 사용자가 확인한 뒤 앱이 기존 `POST /me/schedules`로 합니다.
- 기준 시각 5개(기상 07:00, 아침 08:00, 점심 12:30, 저녁 18:30, 취침 22:30)에 배치하고, 식전은 30분 앞, 식후는 30분 뒤, 공복·식간은 2시간 뒤로 옮깁니다. 요청의 `base_times`로 바꿀 수 있습니다.
- 횟수가 범위면(1일 3~4회) 작은 값으로 제안하고 `confidence`를 `CONFIRM`으로 돌려줍니다.
- 용법에 나이 말이 있으면 나이와 맞는지 확인을 요청합니다. 숫자 기준(만 15세 이상 등)은 생년월일과 맞으면 그대로 추천하고, 숫자 없이 "성인"이라고만 적힌 용법은 항상 확인을 요청합니다.
- **용량(몇 정·몇 mL)은 제안하지 않습니다.** 나이별 용량이 절반 가까워 잘못 고를 위험이 큽니다.
- 먹는 약이 아니거나, 필요할 때만 먹는 약이거나, 횟수를 읽지 못한 약은 짐작하지 않고 `confidence: NONE`으로 돌려줍니다.
- 이미 저장한 제안은 `slots[].saved`로 알려 줍니다. 같은 약·같은 시각을 또 저장하려 하면 `409 DUPLICATE`로 막습니다. (손채은 10/12 검수)
- 병용금기가 있어도 시간을 나눠서 해결하지 않고 `dur_findings`에 경고만 붙입니다.
- 먹는 약 3,520건 중 3,055건(86%)에 제안이 나옵니다. 바로 쓸 만한 제안(`HIGH`)은 나이를 모르면 54건, 생년월일이 있으면 1,057건입니다.

## 남은 작업
- `TODO.md`에 지금 되는 범위와 남은 작업, 팀이 정해야 할 것을 적어 뒀습니다. (10/11 인계 자료)

## 참고
- 에러 응답은 `{"detail": 메시지, "code": NOT_FOUND 등}` 형식입니다.
- DB 구조는 김서현 `pillflow_db_erd_spec.docx`를 따릅니다.
