import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillflow/widgets/voice_search.dart';

/// 실제 마이크 대신 정해 둔 결과를 돌려주는 가짜 인식기
class _FakeRecognizer implements VoiceRecognizer {
  _FakeRecognizer({this.available = true, this.words = '', this.errorCode});
  final bool available;
  final String words;
  final String? errorCode;
  void Function(String)? _onError;

  @override
  Future<bool> init({required void Function(String code) onError}) async {
    _onError = onError;
    return available;
  }

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
  }) async {
    onLevel?.call(0.5);
    if (errorCode != null) {
      _onError?.call(errorCode!);
      return;
    }
    onResult(words, true);
  }

  @override
  Future<void> stop() async {}
}

Widget _host(VoiceRecognizer rec, void Function(String?) onDone) => ProviderScope(
      overrides: [voiceRecognizerProvider.overrideWithValue(rec)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => onDone(await showVoiceSearch(context)),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

/// 테스트 기본 화면(800×600)은 가로로 넓어 실제 폰과 달라서, 폰 크기(갤럭시 A36 정도)로 맞춤
void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  test('말로 찾기: 띄어쓰기·문장부호를 빼서 검색어로 만든다', () {
    expect(normalizeSpoken('타이레놀 정.'), '타이레놀정');
    expect(normalizeSpoken(' 베아제 '), '베아제');
    expect(normalizeSpoken('...'), '');
  });

  test('말로 찾기: 오류 문구는 항상 다른 방법을 알려 준다', () {
    expect(voiceErrorMessage('error_permission'), contains('직접 입력'));
    expect(voiceErrorMessage('error_no_match'), contains('다시 말해'));
    expect(voiceErrorMessage('error_network'), contains('직접 입력'));
  });

  testWidgets('말로 찾기: 인식한 이름을 돌려준다', (tester) async {
    _phoneSize(tester);
    String? result;
    await tester.pumpWidget(_host(_FakeRecognizer(words: '타이레놀 정'), (r) => result = r));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(result, '타이레놀정');
  });

  testWidgets('말로 찾기: 마이크를 못 쓰면 안내하고 창을 닫지 않는다', (tester) async {
    _phoneSize(tester);
    String? result = 'unset';
    await tester.pumpWidget(_host(_FakeRecognizer(available: false), (r) => result = r));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('마이크 권한'), findsOneWidget);
    expect(find.text('직접 입력할게요'), findsOneWidget);
    expect(result, 'unset');
    await tester.tap(find.text('직접 입력할게요'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
