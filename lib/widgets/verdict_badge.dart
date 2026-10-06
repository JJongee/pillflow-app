import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// DUR 판정 배지. 색만으로 구분하지 않도록 아이콘 + 글자를 함께 씁니다.
/// "판정 불가"는 초록(안전) 계열을 절대 쓰지 않습니다.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge({super.key, required this.verdict, this.large = false});
  final Verdict verdict;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (verdict) {
      Verdict.contraindicated => (AppColors.danger, AppColors.dangerBg, Icons.warning_amber_rounded),
      Verdict.noKnownIssue => (AppColors.neutral, AppColors.neutralBg, Icons.info_outline),
      Verdict.undetermined => (AppColors.unknown, AppColors.unknownBg, Icons.help_outline),
    };
    final size = large ? 18.0 : 15.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 8 : 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withAlpha(102)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: size + 2, color: fg),
        const SizedBox(width: 6),
        Text(verdict.label, style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
