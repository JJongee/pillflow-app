import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 글자 크게 보기 (교수님 면담 피드백 10/21: 고령자 가독성)
/// 켜면 앱 전체 글자를 1.3배로 키움. 폰에 저장해서 앱을 다시 켜도 유지.
const largeTextFactor = 1.3;
const _prefKey = 'large_text';

class LargeTextNotifier extends StateNotifier<bool> {
  LargeTextNotifier() : super(false) {
    load();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) state = p.getBool(_prefKey) ?? false;
    } catch (_) {
      // 저장소를 못 읽어도 기본 크기로 동작
    }
  }

  Future<void> set(bool on) async {
    state = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, on);
    } catch (_) {}
  }
}

/// 처음 '오늘' 탭에 들어왔을 때 글자 크기를 한 번 물어봤는지 (이 폰 기준)
const _askedKey = 'large_text_asked';

Future<bool> textSizeAsked() async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_askedKey) ?? false;
  } catch (_) {
    return true; // 저장소를 못 읽으면 묻지 않음 (매번 뜨는 것보다 나음)
  }
}

Future<void> markTextSizeAsked() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_askedKey, true);
  } catch (_) {}
}

final largeTextProvider = StateNotifierProvider<LargeTextNotifier, bool>((ref) => LargeTextNotifier());

/// 휴대폰 자체 글자 크기 설정 위에 1.3배를 더함. 너무 커져 화면이 깨지지 않게 최대 2배.
TextScaler appTextScaler(TextScaler system, bool large) {
  if (!large) return system;
  final base = system.scale(1);
  return TextScaler.linear((base * largeTextFactor).clamp(1.0, 2.0));
}
