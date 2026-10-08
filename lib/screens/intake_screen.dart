import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/state_views.dart';
import 'settings_screen.dart';

/// 오늘 복용 체크 (복용 기록)
class IntakeScreen extends ConsumerWidget {
  const IntakeScreen({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, IntakeRecord r, IntakeStatus s) async {
    try {
      await ref.read(repositoryProvider).setIntake(scheduleId: r.scheduleId, date: r.date, status: s);
      ref.invalidate(intakesProvider(r.date));
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = todayString();
    final value = ref.watch(intakesProvider(date));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('오늘 · $date'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(intakesProvider(date).future),
        child: AsyncBody<List<IntakeRecord>>(
          value: value,
          onRetry: () => ref.invalidate(intakesProvider(date)),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyView(
                  icon: Icons.event_available_outlined,
                  title: '오늘 먹을 약이 없어요',
                  message: '"시간표" 탭에서 복용 시간을 추가해 주세요.',
                ),
              ]);
            }
            final done = list.where((r) => r.status == IntakeStatus.taken).length;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('$done / ${list.length} 복용', style: t.titleLarge),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: done / list.length, minHeight: 10, borderRadius: BorderRadius.circular(5)),
              const SizedBox(height: 16),
              // 같은 시간에 먹는 약은 카드 하나로 묶고, 약마다 따로 체크 (손채은 10/8 제안)
              ..._byTime(list).entries.map((e) => _TimeCard(
                    time: e.key,
                    records: e.value,
                    onSet: (r, st) => _set(context, ref, r, st),
                  )),
            ]);
          },
        ),
      ),
    );
  }
}

/// 시간별로 묶기 (시간 순서대로)
Map<String, List<IntakeRecord>> _byTime(List<IntakeRecord> list) {
  final sorted = [...list]..sort((a, b) => a.time.compareTo(b.time));
  final out = <String, List<IntakeRecord>>{};
  for (final r in sorted) {
    out.putIfAbsent(r.time, () => []).add(r);
  }
  return out;
}

/// 한 시간대 카드: 08:00 · 2/3 복용 → 약마다 [먹었어요] [건너뛰기]
class _TimeCard extends StatelessWidget {
  const _TimeCard({required this.time, required this.records, required this.onSet});
  final String time;
  final List<IntakeRecord> records;
  final void Function(IntakeRecord, IntakeStatus) onSet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = records.where((r) => r.status == IntakeStatus.taken).length;
    final allDone = done == records.length;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(time, style: t.titleLarge),
            const SizedBox(width: 10),
            Text('약 ${records.length}개', style: t.bodyMedium),
            const Spacer(),
            Text(
              allDone ? '모두 먹었어요' : '$done / ${records.length} 복용',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: allDone ? AppColors.ok : Toss.grey600,
              ),
            ),
          ]),
          for (final r in records) ...[
            const Divider(height: 20),
            _IntakeRow(record: r, onSet: onSet),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _IntakeRow extends StatelessWidget {
  const _IntakeRow({required this.record, required this.onSet});
  final IntakeRecord record;
  final void Function(IntakeRecord, IntakeStatus) onSet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = record;
    final taken = r.status == IntakeStatus.taken;
    final skipped = r.status == IntakeStatus.skipped;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(
            r.itemName,
            style: t.titleMedium?.copyWith(fontSize: 17, color: skipped ? Toss.grey500 : null),
          ),
        ),
        if (skipped) Text('건너뜀', style: t.bodySmall?.copyWith(fontSize: 14)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: taken
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.ok, minimumSize: const Size(0, 48)),
                  onPressed: () => onSet(r, IntakeStatus.pending),
                  icon: const Icon(Icons.check),
                  label: const Text('먹었어요'),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => onSet(r, IntakeStatus.taken),
                  icon: const Icon(Icons.check_box_outline_blank),
                  label: const Text('먹었어요'),
                ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => onSet(r, skipped ? IntakeStatus.pending : IntakeStatus.skipped),
          child: Text(skipped ? '건너뜀 취소' : '건너뛰기'),
        ),
      ]),
    ]);
  }
}
