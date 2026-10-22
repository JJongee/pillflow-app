import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/text_size.dart';
import 'state_views.dart';

/// 가입 후 처음 '오늘' 화면에서 한 번만: 글자 크기 고르기 → "설정에서 언제든 바꿀 수 있어요" 안내
Future<void> maybeAskTextSize(BuildContext context, WidgetRef ref) async {
  if (await textSizeAsked()) return;
  if (!context.mounted) return;
  final large = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _TextSizeDialog(),
  );
  await markTextSizeAsked();
  if (large != null) await ref.read(largeTextProvider.notifier).set(large);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      duration: Duration(seconds: 5),
      content: Text('글자 크기는 언제든지 오른쪽 위 ⚙ 설정 → 보기에서 바꿀 수 있어요.', style: TextStyle(fontSize: 16)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _TextSizeDialog extends StatefulWidget {
  const _TextSizeDialog();

  @override
  State<_TextSizeDialog> createState() => _TextSizeDialogState();
}

class _TextSizeDialogState extends State<_TextSizeDialog> {
  bool _large = false;

  @override
  Widget build(BuildContext context) {
    final system = MediaQuery.textScalerOf(context).scale(1);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Toss.blue50, shape: BoxShape.circle),
              child: const Icon(Icons.text_fields_rounded, color: Toss.blue, size: 30),
            ),
          ),
          const SizedBox(height: 14),
          const Text('글자 크기를 골라 주세요',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(keepWords('보기 편한 크기로 앱 전체 글자가 바뀌어요.'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, color: Toss.grey600)),
          const SizedBox(height: 18),
          // 보통 / 크게 나란히
          Row(children: [
            Expanded(child: _Option(label: '보통', glyphSize: 26, selected: !_large, onTap: () => setState(() => _large = false))),
            const SizedBox(width: 10),
            Expanded(child: _Option(label: '크게', glyphSize: 36, selected: _large, onTap: () => setState(() => _large = true))),
          ]),
          const SizedBox(height: 14),
          // 고른 크기로 미리보기
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Toss.grey50, borderRadius: BorderRadius.circular(16)),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(system * (_large ? largeTextFactor : 1.0)),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('미리보기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Toss.grey500)),
                SizedBox(height: 6),
                Row(children: [
                  Text('08:00', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  SizedBox(width: 10),
                  Expanded(child: Text('타이레놀정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ]),
                SizedBox(height: 2),
                Text('식후 30분에 1정', style: TextStyle(fontSize: 14, color: Toss.grey600)),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.pop(context, _large),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('이 크기로 할게요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

/// 선택지 카드: 큰 '가'로 크기 차이를 바로 보여 줌
class _Option extends StatelessWidget {
  const _Option({required this.label, required this.glyphSize, required this.selected, required this.onTap});
  final String label;
  final double glyphSize;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Toss.blue50 : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? Toss.blue : Toss.grey200, width: selected ? 2 : 1.5),
          ),
          child: Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // '가'는 휴대폰 글자 설정과 상관없이 고정 크기로 (두 칸 크기 차이가 그대로 보이게)
                Text('가',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                        fontSize: glyphSize, fontWeight: FontWeight.w800, color: selected ? Toss.blue : Toss.grey700)),
                const SizedBox(height: 4),
                Text(label,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: selected ? Toss.blue : Toss.grey600)),
              ]),
            ),
            if (selected)
              const Positioned(top: 8, right: 8, child: Icon(Icons.check_circle, color: Toss.blue, size: 22)),
          ]),
        ),
      ),
    );
  }
}
