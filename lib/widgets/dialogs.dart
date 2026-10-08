import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/models.dart';
import 'state_views.dart';

/// 글자 하나를 입력받는 공통 다이얼로그.
/// 컨트롤러를 다이얼로그 안에서 만들고 정리하므로 닫히는 애니메이션 중에도 안전합니다.
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    super.key,
    required this.title,
    this.initial = '',
    this.hint,
    this.helper,
    this.keyboardType,
    this.maxLength,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final int? maxLength;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _c,
          autofocus: true,
          keyboardType: widget.keyboardType,
          maxLength: widget.maxLength,
          decoration: InputDecoration(hintText: widget.hint, helperText: widget.helper),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text.trim()), child: const Text('저장')),
        ],
      );
}

/// 생년월일 입력 다이얼로그 (년·월·일 칸). 달력 대신 숫자 칸이라 어르신도 입력하기 쉬움
class BirthDateDialog extends StatefulWidget {
  const BirthDateDialog({super.key, this.initial, this.initialYear});
  final DateTime? initial;
  final int? initialYear; // 태어난 해만 있던 사용자는 연도 칸을 채워 둠

  @override
  State<BirthDateDialog> createState() => _BirthDateDialogState();
}

class _BirthDateDialogState extends State<BirthDateDialog> {
  late final _y = TextEditingController(text: (widget.initial?.year ?? widget.initialYear)?.toString() ?? '');
  late final _m = TextEditingController(text: widget.initial?.month.toString() ?? '');
  late final _d = TextEditingController(text: widget.initial?.day.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _y.dispose();
    _m.dispose();
    _d.dispose();
    super.dispose();
  }

  /// 실제로 있는 날짜인지, 1900-01-01 ~ 오늘 사이인지 확인
  static DateTime? check(String y, String m, String d) {
    final yy = int.tryParse(y.trim()), mm = int.tryParse(m.trim()), dd = int.tryParse(d.trim());
    if (yy == null || mm == null || dd == null) return null;
    final date = DateTime(yy, mm, dd);
    if (date.year != yy || date.month != mm || date.day != dd) return null; // 2월 30일 등
    final now = DateTime.now();
    if (date.isBefore(DateTime(1900)) || date.isAfter(DateTime(now.year, now.month, now.day))) return null;
    return date;
  }

  void _submit() {
    final date = check(_y.text, _m.text, _d.text);
    if (date == null) {
      setState(() => _error = '날짜를 다시 확인해 주세요.');
      return;
    }
    Navigator.pop(context, date);
  }

  @override
  Widget build(BuildContext context) {
    Widget box(TextEditingController c, String label, int len, {int flex = 1, bool last = false}) => Expanded(
          flex: flex,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            maxLength: len,
            textAlign: TextAlign.center,
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            onSubmitted: last ? (_) => _submit() : null,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: label, counterText: ''),
          ),
        );
    return AlertDialog(
      title: const Text('생년월일'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          box(_y, '년', 4, flex: 3),
          const SizedBox(width: 8),
          box(_m, '월', 2, flex: 2),
          const SizedBox(width: 8),
          box(_d, '일', 2, flex: 2, last: true),
        ]),
        const SizedBox(height: 10),
        Text('나이에 따라 금기인 약과 나이별 용법을 확인할 때만 써요.', style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}

/// 생년월일 입력 → 저장 → 관련 화면 새로고침. DUR 결과·설정·시간표 제안 화면에서 같이 씁니다.
/// 저장했으면 true
Future<bool> editBirthDate(BuildContext context, WidgetRef ref, Profile? current) async {
  final date = await showDialog<DateTime>(
    context: context,
    builder: (_) => BirthDateDialog(initial: current?.birthDate, initialYear: current?.birthYear),
  );
  if (date == null || !context.mounted) return false;
  try {
    await ref.read(repositoryProvider).setBirthDate(date);
    ref.invalidate(profileProvider);
    ref.invalidate(durCheckProvider);
    if (context.mounted) showSnack(context, '저장했어요.');
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
    return false;
  }
}
