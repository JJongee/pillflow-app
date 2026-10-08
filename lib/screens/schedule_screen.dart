import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/dose_field.dart';
import '../widgets/state_views.dart';
import 'schedule_suggest_screen.dart';

/// 사용자가 직접 지정하는 복용 시간표 (자동 생성은 후속 개발)
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final drugs = await ref.read(myDrugsProvider.future);
    if (!context.mounted) return;
    if (drugs.isEmpty) {
      showSnack(context, '먼저 "약 찾기"에서 약을 등록해 주세요.');
      return;
    }
    await _openSheet(context, ref, drugs: drugs);
  }

  Future<void> _suggest(BuildContext context, WidgetRef ref) async {
    final drugs = await ref.read(myDrugsProvider.future);
    if (!context.mounted) return;
    if (drugs.isEmpty) {
      showSnack(context, '먼저 "약 찾기"에서 약을 등록해 주세요.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScheduleSuggestScreen()));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ScheduleItem s) =>
      _openSheet(context, ref, drugs: const [], existing: s);

  Future<void> _openSheet(BuildContext context, WidgetRef ref,
      {required List<UserDrug> drugs, ScheduleItem? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ScheduleSheet(drugs: drugs, existing: existing),
    );
    if (saved == true) {
      ref.invalidate(schedulesProvider);
      ref.invalidate(intakesProvider(todayString()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(schedulesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('복용 시간표'),
        actions: [
          TextButton.icon(
            onPressed: () => _suggest(context, ref),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('자동 제안'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncBody<List<ScheduleItem>>(
        value: value,
        onRetry: () => ref.invalidate(schedulesProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyView(
              icon: Icons.schedule,
              title: '아직 정한 복용 시간이 없어요',
              message: '약마다 먹을 시간을 정해 두면 "오늘" 탭에서 체크할 수 있어요.',
              action: Column(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  onPressed: () => _suggest(context, ref),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('용법 보고 자동으로 제안받기'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _add(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('직접 추가'),
                ),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = list[i];
              return ListTile(
                leading: Text(s.time, style: Theme.of(context).textTheme.titleLarge),
                title: Text(s.itemName),
                subtitle: Text([s.mealRelation.label, s.doseText].whereType<String>().join(' · ')),
                onTap: () => _edit(context, ref, s), // 눌러서 수정
                trailing: IconButton(
                  tooltip: '삭제',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await ref.read(repositoryProvider).deleteSchedule(s.id);
                      ref.invalidate(schedulesProvider);
                      ref.invalidate(intakesProvider(todayString()));
                    } catch (e) {
                      if (context.mounted) showSnack(context, e.toString());
                    }
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: (value.valueOrNull?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('시간 추가', style: TextStyle(fontSize: 17)),
            )
          : null,
    );
  }
}

/// 복용 시간 추가/수정 시트. [existing] 이 있으면 수정 모드(약은 바꿀 수 없음).
class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet({required this.drugs, this.existing});
  final List<UserDrug> drugs;
  final ScheduleItem? existing;

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  bool get _isEdit => widget.existing != null;
  late UserDrug? _drug = widget.drugs.isEmpty ? null : widget.drugs.first;
  late TimeOfDay _time = _parse(widget.existing?.time) ?? const TimeOfDay(hour: 8, minute: 30);
  late MealRelation _meal = widget.existing?.mealRelation ?? MealRelation.after;
  late final _dose = TextEditingController(text: _isEdit ? (widget.existing!.doseText ?? '') : '1정');
  bool _saving = false;

  static TimeOfDay? _parse(String? hhmm) {
    if (hhmm == null) return null;
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return (h == null || m == null) ? null : TimeOfDay(hour: h, minute: m);
  }

  @override
  void dispose() {
    _dose.dispose();
    super.dispose();
  }

  String get _hhmm =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() => _saving = true);
    final dose = _dose.text.trim().isEmpty ? null : _dose.text.trim();
    final repo = ref.read(repositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateSchedule(widget.existing!.id, time: _hhmm, mealRelation: _meal, doseText: dose);
      } else {
        await repo.addSchedule(userDrugId: _drug!.id, time: _hhmm, mealRelation: _meal, doseText: dose);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_isEdit ? '복용 시간 수정' : '복용 시간 추가', style: t.titleLarge),
        const SizedBox(height: 16),
        if (_isEdit)
          InputDecorator(
            decoration: const InputDecoration(labelText: '약'),
            child: Text(widget.existing!.itemName, style: const TextStyle(fontSize: 17)),
          )
        else
          DropdownButtonFormField<UserDrug>(
            value: _drug,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '약'),
            items: widget.drugs
                .map((d) => DropdownMenuItem(value: d, child: Text(d.itemName, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (d) => setState(() => _drug = d ?? _drug),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.access_time),
          label: Text('시간  $_hhmm', style: const TextStyle(fontSize: 20)),
          onPressed: () async {
            final picked = await showTimePicker(context: context, initialTime: _time);
            if (picked != null) setState(() => _time = picked);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: MealRelation.values
              .map((m) => ChoiceChip(
                    label: Text(m.label, style: const TextStyle(fontSize: 16)),
                    selected: _meal == m,
                    onSelected: (_) => setState(() => _meal = m),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        DoseField(controller: _dose),
        const SizedBox(height: 20),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '저장 중…' : '저장')),
      ]),
    );
  }
}
