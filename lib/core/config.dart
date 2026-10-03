/// 앱 전역 설정.
///
/// 실행할 때 바꿀 수 있습니다:
///   flutter run                                   → 목업 데이터 (서버 없이 동작)
///   flutter run --dart-define=USE_MOCK=false      → 로컬 서버 연결
///   flutter run --dart-define=USE_MOCK=false --dart-define=API_BASE=http://192.168.0.10:8000/api/v1
class AppConfig {
  static const bool useMock =
      bool.fromEnvironment('USE_MOCK', defaultValue: true);

  /// 안드로이드 에뮬레이터에서 개발 PC의 localhost는 10.0.2.2 입니다.
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
}
