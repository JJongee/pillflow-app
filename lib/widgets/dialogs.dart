import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
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

/// 태어난 해 입력 → 저장 → 관련 화면 새로고침. DUR 결과 화면과 설정 화면에서 같이 씁니다.
Future<void> editBirthYear(BuildContext context, WidgetRef ref, int? current) async {
  final text = await showDialog<String>(
    context: context,
    builder: (_) => TextInputDialog(
      title: '태어난 해',
      initial: current?.toString() ?? '',
      hint: '예: 1958',
      helper: '나이에 따라 금기인 약을 확인할 때만 써요.',
      keyboardType: TextInputType.number,
      maxLength: 4,
    ),
  );
  if (text == null || !context.mounted) return;
  final y = int.tryParse(text);
  if (y == null || y < 1900 || y > DateTime.now().year) {
    showSnack(context, '태어난 해를 다시 확인해 주세요.');
    return;
  }
  try {
    await ref.read(repositoryProvider).setBirthYear(y);
    if (!context.mounted) return;
    ref.invalidate(birthYearProvider);
    ref.invalidate(durCheckProvider);
    if (context.mounted) showSnack(context, '저장했어요.');
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
  }
}
