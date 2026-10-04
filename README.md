# 필플로우 앱 (Flutter) — 고연수 작업 시작본

서버 없이 **목업 데이터**로 바로 돌아가는 앱 골격입니다.
10/5 실제 API가 나오면 실행 옵션만 바꿔서 서버에 붙습니다.

## 처음 실행 (한 번만)

```bash
cd pillflow_app
flutter create . --project-name pillflow --platforms=android,ios   # android/ios 폴더 생성 (기존 lib, test는 그대로 둠)
flutter pub get
flutter test          # 3개 통과해야 정상
flutter run           # 목업 데이터로 실행
```

> 이 코드는 Flutter를 설치할 수 없는 환경에서 작성해서 **아직 한 번도 빌드해 보지 않았습니다.**
> `flutter analyze`에서 오류가 나면 그 메시지를 그대로 보내주세요.

### 로컬 서버에 연결할 때 (10/5부터)

```bash
flutter run --dart-define=USE_MOCK=false                                   # 에뮬레이터 → 개발 PC (10.0.2.2:8000)
flutter run --dart-define=USE_MOCK=false --dart-define=API_BASE=http://192.168.0.10:8000/api/v1   # 실기기
```

안드로이드는 `http://` 주소를 기본으로 막습니다. `android/app/src/main/AndroidManifest.xml`의 `<application>` 태그에 아래 속성을 추가하세요.

```xml
android:usesCleartextTraffic="true"
```

## 시연 시나리오 (목업)

1. **약 찾기** 탭에서 `바이엘아스피린`을 검색해 *바이엘아스피린정500밀리그람*을 등록하고, `케토신`을 검색해 *케토신주사*를 등록합니다.
2. **내 약** 탭에서 "함께 먹어도 되는지 확인"을 누르면 **병용금기** 경고가 나옵니다. 고시 20080068, 중증의 위장관계 이상반응이 표시되고, 시간 분리 대신 상담을 안내합니다.
3. `게보린`을 등록하고 태어난 해를 2015로 입력하면 **연령금기**(15세 미만)가 나옵니다.
4. `활명수`를 등록하면 **판정 불가**로 나옵니다. DUR 데이터에 없는 약이기 때문입니다.
4-1. `멕시롱액` + `코메키나캡슐`을 등록하면 **병용금기**가 나옵니다. 김서현 님 DB에서 금기 기록이 확인된 조합이라, 서버 모드에서도 같은 결과가 나와야 합니다(연결 확인용).
5. **시간표** 탭에서 시간을 추가하고, **오늘** 탭에서 복용 체크를 합니다.

목업 규칙은 업로드한 병용금기·연령금기 파일의 실제 행에서 가져왔습니다.
검색은 e약은요 CSV 전체(4,741품목)에서 됩니다. 목업 DUR 규칙은 위 예시 약들에만 들어 있어서, 다른 약은 모두 **판정 불가**로 나옵니다.

## UI 검수

설정(오늘 탭 ⚙️) → **화면 상태 미리보기**에서 로딩·검색 0건·서버 오류·로그인 실패·빈 화면·DUR 3단계·150자 약품명을 바로 볼 수 있습니다.

## 폴더 구조

```
lib/
  main.dart, app.dart          하단 탭 4개 (오늘 · 약 찾기 · 내 약 · 시간표)
  core/config.dart             USE_MOCK, API_BASE 설정
  core/theme.dart              큰 글씨·고대비 테마, 판정 색상 (디자인 확정 시 여기만 수정)
  models/models.dart           API 초안과 1:1 모델
  data/repository.dart         화면이 쓰는 인터페이스
  data/mock_repository.dart    목업 (assets/mock/*.json)
  data/api_repository.dart     실제 서버 (Dio)  ← 10/5에 맞춰 볼 곳
  data/providers.dart          Riverpod provider
  widgets/                     로딩·빈 결과·오류 상태, 판정 배지, 약 이미지, 접는 설명 카드
  screens/                     검색, 상세, 내 약, DUR 결과, 시간표, 오늘(복용 기록)
assets/mock/                   drugs.json (CSV 전체 4,741품목 + DUR 품목 1개, 12MB), dur_rules.json
docs/api_contract.md           주연우 님과 합의할 API 초안
```

## 지켜야 할 안전 원칙 (코드에 반영됨)

- DUR 데이터에 없는 약은 **판정 불가**로 표시합니다. 초록색이나 "안전" 문구를 쓰지 않습니다.
- 병용금기는 시간을 나눠서 해결하지 않습니다. 경고를 보여주고 의사·약사 상담을 안내합니다.
- 경고에는 고시번호, 고시일자, 조건(`비고`)을 함께 표시합니다.

## 아직 안 한 것 / 다음 할 일

- [ ] 손채은 님 와이어프레임 반영 (`core/theme.dart`, 각 screen)
- [ ] 10/5 서버 연동: `api_repository.dart` 경로·필드를 실제 서버와 대조
- [ ] 로그인 화면 (인증 방식 확정 후, `ApiRepository(tokenProvider: ...)`)
- [ ] 약 식별자 통일 방식 확정 후 `item_seq` 처리 수정 (e약은요 품목기준코드 vs DUR 보험코드)
