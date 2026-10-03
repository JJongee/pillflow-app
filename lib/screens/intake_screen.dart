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
              ...list.map((r) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(r.time, style: t.titleLarge),
                          const SizedBox(width: 12),
                          Expanded(child: Text(r.itemName, style: t.titleMedium?.copyWith(fontSize: 18))),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: r.status == IntakeStatus.taken
                                ? FilledButton.icon(
                                    style: FilledButton.styleFrom(backgroundColor: AppColors.ok),
                                    onPressed: () => _set(context, ref, r, IntakeStatus.pending),
                                    icon: const Icon(Icons.check),
                                    label: const Text('먹었어요'),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: () => _set(context, ref, r, IntakeStatus.taken),
                                    icon: const Icon(Icons.check_box_outline_blank),
                                    label: const Text('먹었어요'),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _set(
                              context,
                              ref,
                              r,
                              r.status == IntakeStatus.skipped ? IntakeStatus.pending : IntakeStatus.skipped,
                            ),
                            child: Text(r.status == IntakeStatus.skipped ? '건너뜀 취소' : '건너뛰기'),
                          ),
                        ]),
                      ]),
                    ),
                  )),
            ]);
          },
        ),
      ),
    );
  }
}
