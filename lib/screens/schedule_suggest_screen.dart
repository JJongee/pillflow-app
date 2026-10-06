import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/state_views.dart';

/// 자동 시간표 제안 (POST /me/schedules/suggest)
/// - 서버는 제안만 하고 저장하지 않음 → 사용자가 고른 칸만 기존 POST /me/schedules 로 저장
/// - HIGH: 미리 선택 / CONFIRM: 주의 문구를 먼저 보여 주고 사용자가 직접 선택 / NONE: 직접 입력 안내
/// - 금기 조합이 있어도 시간을 나눠 해결하지 않음 (상담 안내)
class ScheduleSuggestScreen extends ConsumerStatefulWidget {
  const ScheduleSuggestScreen({super.key});

  @override
  ConsumerState<ScheduleSuggestScreen> createState() => _ScheduleSuggestScreenState();
}

class _SlotState {
  _SlotState(this.time, this.meal, this.selected);
  TimeOfDay time;
  MealRelation meal;
  bool selected;
}

class _ScheduleSuggestScreenState extends ConsumerState<ScheduleSuggestScreen> {
  late Future<ScheduleSuggestResult> _future = _load();
  final Map<int, List<_SlotState>> _slots = {};
  final Map<int, TextEditingController> _dose = {};
  Map<int, int> _existing = {}; // user_drug_id → 이미 있는 시간표 개수
  bool _saving = false;

  Future<ScheduleSuggestResult> _load() async {
    final repo = ref.read(repositoryProvider);
    final schedules = await repo.getSchedules();
    final res = await repo.suggestSchedules();
    final existing = <int, int>{};
    for (final s in schedules) {
      existing[s.userDrugId] = (existing[s.userDrugId] ?? 0) + 1;
    }
    _existing = existing;
    _slots.clear();
    for (final s in res.suggestions) {
      // 확실한 제안이고 아직 시간표가 없는 약만 미리 선택
      final preselect = s.confidence == SuggestConfidence.high && (existing[s.userDrugId] ?? 0) == 0;
      _slots[s.userDrugId] = [
        for (final slot in s.slots) _SlotState(_parse(slot.time), slot.mealRelation, preselect),
      ];
      _dose.putIfAbsent(s.userDrugId, TextEditingController.new);
    }
    if (mounted) setState(() {}); // 아래 저장 버튼도 미리 선택된 개수로 갱신
    return res;
  }

  @override
  void dispose() {
    for (final c in _dose.values) {
      c.dispose();
    }
    super.dispose();
  }

  static TimeOfDay _parse(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.tryParse(p.first) ?? 8, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int get _selectedCount => _slots.values.expand((l) => l).where((s) => s.selected).length;

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    var saved = 0;
    try {
      for (final entry in _slots.entries) {
        final dose = _dose[entry.key]?.text.trim();
        for (final s in entry.value.where((s) => s.selected)) {
          await repo.addSchedule(
            userDrugId: entry.key,
            time: _fmt(s.time),
            mealRelation: s.meal,
            doseText: (dose == null || dose.isEmpty) ? null : dose,
          );
          saved++;
        }
      }
      ref.invalidate(schedulesProvider);
      ref.invalidate(intakesProvider(todayString()));
      if (!mounted) return;
      showSnack(context, '복용 시간 $saved개를 저장했어요.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      // 일부만 저장됐을 수 있으니 목록을 새로 고칠 수 있게 무효화
      ref.invalidate(schedulesProvider);
      setState(() => _saving = false);
      showSnack(context, saved > 0 ? '$saved개 저장 후 오류가 났어요: $e' : e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('시간표 제안')),
      body: FutureBuilder<ScheduleSuggestResult>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView(message: '제안을 만드는 중이에요');
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: () => setState(() => _future = _load()));
          }
          final r = snap.data!;
          if (r.suggestions.isEmpty) {
            return const EmptyView(
              icon: Icons.medication_outlined,
              title: '제안할 약이 없어요',
              message: '"약 찾기"에서 먹고 있는 약을 먼저 등록해 주세요.',
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
            Text('약 설명서의 용법을 읽어 복용 시간을 제안했어요. 확인하고 저장할 시간만 골라 주세요.', style: t.bodyMedium),
            if (r.durFindings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DurBanner(count: r.durFindings.length),
            ],
            const SizedBox(height: 8),
            ...r.suggestions.map((s) => _SuggestionCard(
                  suggestion: s,
                  slots: _slots[s.userDrugId] ?? const [],
                  dose: _dose[s.userDrugId]!,
                  existing: _existing[s.userDrugId] ?? 0,
                  onChanged: () => setState(() {}),
                  fmt: _fmt,
                )),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...r.notes.map((n) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('· $n', style: t.bodySmall),
                  )),
            ],
          ]);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: (_saving || _selectedCount == 0) ? null : _save,
            child: Text(_saving
                ? '저장 중…'
                : _selectedCount == 0
                    ? '저장할 시간을 골라 주세요'
                    : '선택한 시간 $_selectedCount개 저장'),
          ),
        ),
      ),
    );
  }
}

/// 금기 조합이 있을 때: 시간을 나눠도 해결되지 않음을 먼저 알림
class _DurBanner extends StatelessWidget {
  const _DurBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '함께 먹으면 안 되는 조합이 $count건 있어요. 시간을 나눠도 해결되지 않으니, '
              '"내 약 → 함께 먹어도 되는지 확인"에서 내용을 보고 의사·약사와 먼저 상담해 주세요.',
              style: const TextStyle(color: AppColors.danger, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.slots,
    required this.dose,
    required this.existing,
    required this.onChanged,
    required this.fmt,
  });

  final ScheduleSuggestion suggestion;
  final List<_SlotState> slots;
  final TextEditingController dose;
  final int existing;
  final VoidCallback onChanged;
  final String Function(TimeOfDay) fmt;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = suggestion;
    final (fg, bg) = switch (s.confidence) {
      SuggestConfidence.high => (Toss.blue, Toss.blue50),
      SuggestConfidence.confirm => (AppColors.caution, AppColors.cautionBg),
      SuggestConfidence.none => (Toss.grey700, Toss.grey100),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(s.itemName, style: t.titleMedium?.copyWith(fontSize: 18))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(s.confidence.label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
          if (existing > 0) ...[
            const SizedBox(height: 4),
            Text('이미 시간표에 $existing개 있어요. 겹치지 않게 확인해 주세요.', style: t.bodySmall),
          ],
          // 확인이 필요한 이유를 먼저 보여 줌
          ...s.warnings.map((w) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline, size: 18, color: AppColors.caution),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(w,
                        style: const TextStyle(color: AppColors.caution, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ]),
              )),
          if (s.basis != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Text('용법 원문 · ${s.basis}', style: t.bodySmall?.copyWith(color: Toss.grey700, fontSize: 14)),
            ),
          ],
          const SizedBox(height: 8),
          if (s.confidence == SuggestConfidence.none || slots.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('용법에서 복용 횟수를 읽지 못했어요. 시간표 화면에서 직접 정해 주세요.', style: t.bodyMedium),
            )
          else ...[
            ...slots.map((slot) => _SlotRow(slot: slot, onChanged: onChanged, fmt: fmt)),
            const SizedBox(height: 8),
            TextField(
              controller: dose,
              decoration: const InputDecoration(labelText: '한 번에 먹는 양 (예: 1정)', isDense: true),
            ),
          ],
        ]),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.onChanged, required this.fmt});
  final _SlotState slot;
  final VoidCallback onChanged;
  final String Function(TimeOfDay) fmt;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Checkbox(
            value: slot.selected,
            onChanged: (v) {
              slot.selected = v ?? false;
              onChanged();
            },
          ),
          TextButton(
            onPressed: () async {
              final picked = await showTimePicker(context: context, initialTime: slot.time);
              if (picked != null) {
                slot.time = picked;
                onChanged();
              }
            },
            child: Text(fmt(slot.time), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
          DropdownButton<MealRelation>(
            value: slot.meal,
            underline: const SizedBox.shrink(),
            items: MealRelation.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label, style: const TextStyle(fontSize: 16))))
                .toList(),
            onChanged: (m) {
              if (m != null) {
                slot.meal = m;
                onChanged();
              }
            },
          ),
        ]),
      );
}
