# 필플로우 API 요청·응답 초안 (v0.1, 앱 쪽 제안)

> 작성: 고연수(앱) · 합의 대상: 주연우(서버) · 10/3 합의용 초안
> 앱의 `lib/data/api_repository.dart`가 이 문서 그대로 구현되어 있습니다. 바뀌면 둘 다 고칩니다.

## 공통 규칙

| 항목 | 제안 |
|---|---|
| Base URL | `http://<개발PC IP>:8000/api/v1` (에뮬레이터는 `http://10.0.2.2:8000/api/v1`) |
| 필드 이름 | `snake_case` |
| 날짜 | `YYYY-MM-DD` 문자열로 통일. CSV는 `openDe`=`20210129`, `updateDe`=`2024-05-09`로 형식이 섞여 있고, DUR 고시일자도 `20080101`과 `2011-11-24`가 섞여 있으므로 **서버에서 정규화** |
| 시각 | `HH:mm` (예: `08:30`) |
| 인증 | `Authorization: Bearer <token>` (인증 붙기 전엔 생략 가능) |
| 빈 값 | 없는 필드는 `null` (빈 문자열 `""` 대신). CSV에서 `atpnWarnQesitm` 3,605건, `intrcQesitm` 1,456건, `itemImage` 1,990건이 비어 있음 |
| 에러 | `{ "detail": "사람이 읽을 메시지", "code": "NOT_FOUND" }` + 적절한 HTTP 상태코드 (FastAPI 기본 `detail` 유지) |
| 목록 | `{ "items": [...], "page": 1, "size": 20, "total": 123 }` |

## 1. 약 검색 · 상세

### `GET /drugs?q=타이레놀&page=1&size=20`
```json
{
  "items": [
    {
      "item_seq": "200008591",
      "item_name": "바이엘아스피린정500밀리그람",
      "entp_name": "바이엘코리아(주)",
      "image_url": "https://nedrug.mfds.go.kr/pbp/cmn/itemImageDownload/...",
      "source": "e약은요"
    }
  ],
  "page": 1, "size": 20, "total": 1
}
```
- `item_seq`는 **문자열** (앞자리 0, 보험코드 혼용 대비).
- `source`: `"e약은요"` 또는 `"DUR 품목(보험코드)"` — 데이터 연결 방식이 정해지면 바뀔 수 있음.

### `GET /drugs/{item_seq}`
```json
{
  "item_seq": "200008591",
  "item_name": "...", "entp_name": "...", "image_url": null,
  "efficacy": "효능 문장", "use_method": "용법", "warning": null,
  "caution": "주의사항", "interaction": "상호작용 문장", "side_effect": "...",
  "storage": "보관법", "open_date": "2021-01-29", "update_date": "2024-05-09",
  "source": "e약은요"
}
```
CSV 열 매핑: `efcyQesitm→efficacy`, `useMethodQesitm→use_method`, `atpnWarnQesitm→warning`, `atpnQesitm→caution`, `intrcQesitm→interaction`, `seQesitm→side_effect`, `depositMethodQesitm→storage`, `itemImage→image_url`, `openDe→open_date`, `updateDe→update_date`.

## 2. 내 약

| 메서드 | 경로 | 바디 | 응답 |
|---|---|---|---|
| GET | `/me/drugs` | – | `[UserDrug]` |
| POST | `/me/drugs` | `{ "item_seq": "200008591", "memo": "아침에" }` | `UserDrug` (201) |
| PATCH | `/me/drugs/{id}` | `{ "memo": "..." }` | `UserDrug` |
| DELETE | `/me/drugs/{id}` | – | 204 (연결된 시간표도 같이 삭제) |

```json
// UserDrug
{ "id": 12, "item_seq": "200008591", "item_name": "...", "entp_name": "...",
  "image_url": null, "memo": "아침에", "created_at": "2026-10-05" }
```
- 같은 약 중복 등록 시 `409` + `code: "DUPLICATE"`.

## 3. 복용 시간표 (사용자 지정)

### `GET /me/schedules`
```json
[
  { "id": 3, "user_drug_id": 12, "item_name": "...", "time": "08:30",
    "meal_relation": "AFTER", "dose_text": "1정" }
]
```
- `meal_relation`: `BEFORE`(식전) · `AFTER`(식후) · `EMPTY`(공복) · `NONE`

### `POST /me/schedules` → 201 / `PATCH /me/schedules/{id}` / `DELETE /me/schedules/{id}` → 204
바디: `{ "user_drug_id": 12, "time": "08:30", "meal_relation": "AFTER", "dose_text": "1정" }`

> 이번 단계는 **사용자가 직접 지정**. 자동 시간표 생성은 후속.

## 4. 복용 기록

### `GET /me/intakes?date=2026-10-05`
그날 시간표 전체 + 기록 상태를 합쳐서 반환 (기록 없으면 `PENDING`).
```json
[
  { "schedule_id": 3, "date": "2026-10-05", "time": "08:30", "item_name": "...",
    "status": "TAKEN", "recorded_at": "2026-10-05T08:41:00" }
]
```
- `status`: `TAKEN` · `SKIPPED` · `PENDING`

### `PUT /me/intakes` (같은 schedule_id+date면 덮어쓰기)
바디: `{ "schedule_id": 3, "date": "2026-10-05", "status": "TAKEN" }` → 200

## 5. 프로필 (연령금기 판별용)

`GET /me/profile` → `{ "birth_year": 1960 }` · `PUT /me/profile` 바디 동일.
나이가 없으면 연령금기는 판별하지 않고 `age_unknown: true`로 응답.

## 6. DUR 판별

### `POST /dur/check`
바디: `{ "item_seqs": ["200008591", "EDI-649802851"] }` (생략하면 내 약 전체)

```json
{
  "data_version": "DUR 게시 2609",
  "checked_at": "2026-10-05",
  "age_unknown": false,
  "drugs": [
    { "item_seq": "200008591", "item_name": "...", "verdict": "CONTRAINDICATED" },
    { "item_seq": "195700020", "item_name": "활명수", "verdict": "UNDETERMINED" }
  ],
  "findings": [
    {
      "type": "COMBINATION",
      "item_seqs": ["200008591", "EDI-649802851"],
      "ingredients": ["aspirin", "ketorolac tromethamine"],
      "detail": "중증의 위장관계 이상반응",
      "condition_note": null,
      "notice_no": "20080068",
      "notice_date": "2008-01-01"
    },
    {
      "type": "AGE",
      "item_seqs": ["197900277"],
      "ingredients": ["isopropylantipyrine 함유제제"],
      "detail": "15세 미만 금기 · 이소프로필안티피린 함유제제(단일제, 복합제)",
      "condition_note": null,
      "notice_no": "20110227",
      "notice_date": "2011-11-24"
    }
  ]
}
```
- `verdict` 세 가지 (보고서 5.5 · 체크리스트 기준)
  - `CONTRAINDICATED`: 금기 근거 있음 → **시간 분리로 해결하지 않고** 전문가 상담 안내
  - `NO_KNOWN_ISSUE`: DUR 데이터에 있는 약이고, 이번 조합에서 걸린 규칙 없음
  - `UNDETERMINED`: DUR 데이터에 없는 약 → **절대 "안전"으로 표시하지 않음**
- `condition_note`: 병용금기 파일의 `비고` 그대로 (예: `"48시간 이내 병용금기"`, `"1주에 MTX 15mg 이상 투여시 병용금기"`). 앱에서 반드시 노출.

## 서버 쪽에 확인하고 싶은 것

1. 약 식별자: e약은요 `item_seq`(품목기준코드)와 DUR `제품코드`(보험코드)가 달라서 코드로는 0건 연결됨. 응답의 `item_seq` 하나로 통일할 방법(매핑 테이블 or 접두어 `EDI-`)을 정해야 함.
2. 판별을 성분코드 쌍(약 1,751쌍)으로 할지.
3. 인증 붙는 날짜(10/5)와 로그인 응답 형식.
