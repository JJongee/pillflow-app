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
  const BirthDateDialog({
    super.key,
    this.initial,
    this.initialYear,
    this.title = '생년월일',
    this.helper = '나이에 따라 금기인 약과 나이별 용법을 확인할 때만 써요.',
    this.allowFutureDays = 0,
  });
  final DateTime? initial;
  final int? initialYear; // 태어난 해만 있던 사용자는 연도 칸을 채워 둠
  final String title;
  final String helper;

  /// 오늘 이후 며칠까지 허용할지 (생년월일 0, 복용 기간은 앞으로의 종료 예정일도 허용)
  final int allowFutureDays;

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
  static DateTime? check(String y, String m, String d, {int allowFutureDays = 0}) {
    final yy = int.tryParse(y.trim()), mm = int.tryParse(m.trim()), dd = int.tryParse(d.trim());
    if (yy == null || mm == null || dd == null) return null;
    final date = DateTime(yy, mm, dd);
    if (date.year != yy || date.month != mm || date.day != dd) return null; // 2월 30일 등
    final now = DateTime.now();
    final last = DateTime(now.year, now.month, now.day).add(Duration(days: allowFutureDays));
    if (date.isBefore(DateTime(1900)) || date.isAfter(last)) return null;
    return date;
  }

  void _submit() {
    final date = check(_y.text, _m.text, _d.text, allowFutureDays: widget.allowFutureDays);
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
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          box(_y, '년', 4, flex: 3),
          const SizedBox(width: 8),
          box(_m, '월', 2, flex: 2),
          const SizedBox(width: 8),
          box(_d, '일', 2, flex: 2, last: true),
        ]),
        const SizedBox(height: 10),
        Text(widget.helper, style: Theme.of(context).textTheme.bodySmall),
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

/// 임신 여부 입력 (선택). 응답 안 함은 '임신 아님'과 구분해서 저장. 저장했으면 true
Future<bool> editPregnancy(BuildContext context, WidgetRef ref, Pregnancy current) async {
  final picked = await showDialog<Pregnancy>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('임신 여부'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('선택 입력이에요. 임부금기가 나에게 해당되는지 확인할 때만 써요.', style: TextStyle(fontSize: 14)),
        ),
        for (final p in Pregnancy.values)
          ListTile(
            leading: Icon(p == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: p == current ? Theme.of(ctx).colorScheme.primary : null),
            title: Text(p.label, style: const TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(ctx, p),
          ),
      ],
    ),
  );
  if (picked == null || picked == current || !context.mounted) return false;
  try {
    await ref.read(repositoryProvider).setPregnancy(picked);
    ref.invalidate(profileProvider);
    ref.invalidate(durCheckProvider);
    if (context.mounted) showSnack(context, '저장했어요.');
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
    return false;
  }
}

/// 복용 시작일·종료일 입력 → 저장. 종료일은 비워 둘 수 있음(아직 먹는 중)
Future<void> editDrugPeriod(BuildContext context, WidgetRef ref, UserDrug drug) async {
  final r = await showDialog<(String?, String?)>(
    context: context,
    builder: (_) => _PeriodDialog(drug: drug),
  );
  if (r == null || !context.mounted) return;
  try {
    await ref.read(repositoryProvider).setDrugPeriod(drug.id, startedOn: r.$1, endedOn: r.$2);
    ref.invalidate(myDrugsProvider);
    ref.invalidate(durCheckProvider);
    if (context.mounted) showSnack(context, '저장했어요.');
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
  }
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({required this.drug});
  final UserDrug drug;

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late DateTime? _start = DateTime.tryParse(widget.drug.startedOn ?? '');
  late DateTime? _end = DateTime.tryParse(widget.drug.endedOn ?? '');
  String? _error;

  String _fmt(DateTime? d) => d == null ? '입력 안 함' : '${d.year}.${d.month}.${d.day}';

  Future<void> _pick(bool start) async {
    final d = await showDialog<DateTime>(
      context: context,
      builder: (_) => BirthDateDialog(
        initial: start ? _start : _end,
        title: start ? '복용 시작일' : '복용 종료일',
        helper: start ? '이 약을 처음 먹기 시작한 날이에요.' : '다 먹었거나 먹기를 멈춘 날이에요.',
        allowFutureDays: 365,
      ),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
      } else {
        _end = d;
      }
      _error = null;
    });
  }

  void _save() {
    if (_start != null && _end != null && _end!.isBefore(_start!)) {
      setState(() => _error = '종료일이 시작일보다 빨라요.');
      return;
    }
    Navigator.pop(context, (_start == null ? null : dateString(_start!), _end == null ? null : dateString(_end!)));
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String label, DateTime? v, bool start) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: Text(_fmt(v), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          onTap: () => _pick(start),
          trailing: v == null
              ? const Icon(Icons.edit_calendar_outlined)
              : IconButton(
                  tooltip: '지우기',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    if (start) {
                      _start = null;
                    } else {
                      _end = null;
                    }
                  }),
                ),
        );
    return AlertDialog(
      title: const Text('복용 기간'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.drug.itemName, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        row('시작일', _start, true),
        row('종료일 (아직 먹고 있으면 비워 두세요)', _end, false),
        Text('투여기간주의 약이 나에게 해당되는지 확인할 때 써요. 중간에 멈췄다 다시 먹었다면 약사와 상담해 주세요.',
            style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}

/// 보기 중 하나를 고르는 공통 창 (누구의 약 / 성별)
Future<T?> pickOne<T>(BuildContext context,
    {required String title, String? note, required List<T> options, required T current, required String Function(T) label}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(note, style: const TextStyle(fontSize: 14)),
          ),
        for (final o in options)
          ListTile(
            leading: Icon(o == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: o == current ? Theme.of(ctx).colorScheme.primary : null),
            title: Text(label(o), style: const TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(ctx, o),
          ),
      ],
    ),
  );
}

Future<void> editSubject(BuildContext context, WidgetRef ref, Subject current) async {
  final v = await pickOne<Subject>(context,
      title: '누구의 약을 관리하나요?',
      note: '생년월일·성별·임신 여부는 약을 먹는 분 기준으로 입력해 주세요.',
      options: Subject.values,
      current: current,
      label: (s) => s.label);
  if (v == null || v == current || !context.mounted) return;
  await _saveProfile(context, ref, () => ref.read(repositoryProvider).setSubject(v));
}

/// 성별만 바꿈. 저장된 임신 여부는 건드리지 않음 (서현 U03·U04: 임의 변경 금지, 충돌은 확인 요청)
Future<void> editSex(BuildContext context, WidgetRef ref, Sex current) async {
  final v = await pickOne<Sex>(context,
      title: '성별 (선택)',
      note: '남성이면 임신 여부를 묻지 않아요. 약을 먹는 분 기준이에요.',
      options: Sex.values,
      current: current,
      label: (s) => s.label);
  if (v == null || v == current || !context.mounted) return;
  await _saveProfile(context, ref, () => ref.read(repositoryProvider).setSex(v));
}

Future<void> _saveProfile(BuildContext context, WidgetRef ref, Future<void> Function() save) async {
  try {
    await save();
    ref.invalidate(profileProvider);
    ref.invalidate(durCheckProvider);
    if (context.mounted) showSnack(context, '저장했어요.');
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString());
  }
}
