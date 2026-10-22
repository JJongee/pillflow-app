import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 말로 약 찾기 (STT) — 교수님 면담 피드백 10/21: 고령자 입력 수고 줄이기
/// 휴대폰 기본 음성 인식(안드로이드)을 씀. 테스트에서는 가짜로 바꿔 끼움.
abstract class VoiceRecognizer {
  /// 마이크를 쓸 수 있으면 true (권한 거부·인식기 없음이면 false)
  Future<bool> init({required void Function(String code) onError});

  /// 말하는 동안 중간 결과(isFinal=false), 끝나면 최종 결과(isFinal=true)
  /// onLevel: 목소리 크기 (0~1로 정리된 값) — 듣고 있다는 걸 화면에 보여 줄 때 씀
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
  });

  Future<void> stop();
}

class SttRecognizer implements VoiceRecognizer {
  final _stt = SpeechToText();

  @override
  Future<bool> init({required void Function(String code) onError}) =>
      _stt.initialize(onError: (SpeechRecognitionError e) => onError(e.errorMsg));

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
  }) =>
      _stt.listen(
        onResult: (SpeechRecognitionResult r) => onResult(r.recognizedWords, r.finalResult),
        // 안드로이드는 대략 -2(조용함)~10(큰 소리) 값이 옴 → 0~1로 정리
        onSoundLevelChange: onLevel == null ? null : (db) => onLevel(((db + 2) / 12).clamp(0.0, 1.0)),
        localeId: 'ko_KR',
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );

  @override
  Future<void> stop() => _stt.stop();
}

final voiceRecognizerProvider = Provider<VoiceRecognizer>((ref) => SttRecognizer());

/// "타이레놀 정." → "타이레놀정" (약 이름은 붙여 쓰는 경우가 많아 띄어쓰기·문장부호를 뺌)
String normalizeSpoken(String s) => s.replaceAll(RegExp(r'[.,!?~]'), '').replaceAll(RegExp(r'\s+'), '').trim();

/// 오류 코드 → 사용자 문구 (항상 직접 입력이라는 대안을 같이 알려 줌)
String voiceErrorMessage(String code) {
  if (code.contains('permission')) {
    return '마이크를 쓸 수 없어요. 휴대폰 설정에서 마이크 권한을 허용하거나, 직접 입력해 주세요.';
  }
  if (code.contains('no_match') || code.contains('speech_timeout')) {
    return '말씀을 알아듣지 못했어요. 다시 말해 주세요.';
  }
  if (code.contains('network')) {
    return '인터넷 연결을 확인해 주세요. 직접 입력해도 돼요.';
  }
  return '음성 인식이 잠시 안 돼요. 다시 시도하거나 직접 입력해 주세요.';
}

/// 아래에서 올라오는 '말로 찾기' 창. 인식한 검색어(정리된 값)를 돌려줌, 취소하면 null
Future<String?> showVoiceSearch(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true, // 기본 높이 제한(화면의 9/16)을 풀어 내용만큼 올라오게 — 작은 화면에서 잘림 방지
      builder: (_) => const _VoiceSheet(),
    );

class _VoiceSheet extends ConsumerStatefulWidget {
  const _VoiceSheet();

  @override
  ConsumerState<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<_VoiceSheet> {
  late final VoiceRecognizer _rec;
  String _text = '';
  String? _error;
  bool _listening = false;
  bool _done = false;
  double _level = 0; // 목소리 크기 0~1

  @override
  void initState() {
    super.initState();
    _rec = ref.read(voiceRecognizerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (_listening) _rec.stop();
    super.dispose();
  }

  void _fail(String message) {
    if (!mounted || _done) return;
    setState(() {
      _listening = false;
      _error = message;
    });
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _text = '';
      _level = 0;
      _listening = true;
    });
    final ok = await _rec.init(onError: (code) => _fail(voiceErrorMessage(code)));
    if (!mounted) return;
    if (!ok) {
      _fail(voiceErrorMessage('permission'));
      return;
    }
    await _rec.start(onResult: (text, isFinal) {
      if (!mounted || _done) return;
      setState(() => _text = text);
      if (!isFinal) return;
      final q = normalizeSpoken(text);
      if (q.isEmpty) {
        _fail(voiceErrorMessage('no_match'));
        return;
      }
      _done = true;
      _listening = false;
      Navigator.of(context).pop(q);
    }, onLevel: (v) {
      if (mounted && _listening) setState(() => _level = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final title = _error ?? (_listening ? '약 이름을 말씀해 주세요' : '잠시만요');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 목소리 크기에 따라 마이크 둘레 원이 커졌다 작아짐 → 듣고 있다는 걸 바로 알 수 있게
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(alignment: Alignment.center, children: [
              if (_listening) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 96 + 64 * _level,
                  height: 96 + 64 * _level,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary.withAlpha(40)),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 92 + 32 * _level,
                  height: 92 + 32 * _level,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary.withAlpha(70)),
                ),
              ],
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _error != null
                      ? scheme.errorContainer
                      : _listening
                          ? scheme.primary
                          : scheme.primaryContainer,
                ),
                child: Icon(
                  _error != null ? Icons.mic_off : Icons.mic,
                  size: 48,
                  color: _error != null
                      ? scheme.error
                      : _listening
                          ? scheme.onPrimary
                          : scheme.primary,
                ),
              ),
            ]),
          ),
          if (_listening)
            Text('듣고 있어요', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 21)),
          const SizedBox(height: 10),
          Text(
            _text.isEmpty ? '예: "타이레놀", "베아제"' : _text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _text.isEmpty ? 16 : 24,
              fontWeight: _text.isEmpty ? FontWeight.w400 : FontWeight.w800,
              color: _text.isEmpty ? Colors.grey.shade600 : null,
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                child: const Text('직접 입력할게요', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _listening
                  ? FilledButton(
                      onPressed: _rec.stop, // 멈추면 지금까지 말한 내용이 최종 결과로 옴
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      child: const Text('다 말했어요', style: TextStyle(fontSize: 16)),
                    )
                  : FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.mic),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      label: const Text('다시 말하기', style: TextStyle(fontSize: 16)),
                    ),
            ),
          ]),
        ]),
      ),
    );
  }
}
