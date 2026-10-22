import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillflow/data/text_size.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('글자 크게 보기: 끄면 휴대폰 설정 그대로, 켜면 1.3배 (최대 2배)', () {
    expect(appTextScaler(TextScaler.noScaling, false).scale(10), 10);
    expect(appTextScaler(TextScaler.noScaling, true).scale(10), closeTo(13, 0.001));
    // 휴대폰 글자를 이미 1.2배로 키운 사람 → 1.56배
    expect(appTextScaler(const TextScaler.linear(1.2), true).scale(10), closeTo(15.6, 0.001));
    // 너무 커지지 않게 최대 2배
    expect(appTextScaler(const TextScaler.linear(1.8), true).scale(10), closeTo(20, 0.001));
  });

  test('글자 크게 보기: 켠 값이 저장돼 다시 켜도 유지된다', () async {
    SharedPreferences.setMockInitialValues({});
    final a = LargeTextNotifier();
    await a.load();
    expect(a.state, isFalse);
    await a.set(true);
    final b = LargeTextNotifier(); // 앱을 다시 켠 상황
    await b.load();
    expect(b.state, isTrue);
  });
}
