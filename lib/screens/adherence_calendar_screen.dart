import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/adherence.dart';
import '../models/models.dart';
import '../widgets/adherence_widgets.dart';
import '../widgets/state_views.dart';

/// 복용 달력: 한 달 동안 날짜별 다 먹음 / 일부 / 못 먹음
class AdherenceCalendarScreen extends ConsumerStatefulWidget {
  const AdherenceCalendarScreen({super.key});

  @override
  ConsumerState<AdherenceCalendarScreen> createState() => _AdherenceCalendarScreenState();
}

class _AdherenceCalendarScreenState extends ConsumerState<AdherenceCalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isThisMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _move(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final days = monthOf(_month.year, _month.month);
    final value = ref.watch(daySummariesProvider(rangeKey(days)));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('복용 달력')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Row(children: [
          IconButton(tooltip: '이전 달', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left, size: 30)),
          Expanded(
            child: Text('${_month.year}년 ${_month.month}월',
                textAlign: TextAlign.center, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: '다음 달',
            onPressed: _isThisMonth ? null : () => _move(1), // 앞으로의 달은 기록이 없어서 막음
            icon: const Icon(Icons.chevron_right, size: 30),
          ),
        ]),
        const SizedBox(height: 8),
        AsyncBody<List<DaySummary>>(
          value: value,
          onRetry: () => ref.invalidate(daySummariesProvider(rangeKey(days))),
          data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Totals(list: list),
            const SizedBox(height: 14),
            _MonthGrid(month: _month, list: list),
            const SizedBox(height: 14),
            const AdherenceLegend(),
            const SizedBox(height: 10),
            Text('날짜를 누르면 그날 먹은 약을 볼 수 있어요.', style: t.bodySmall?.copyWith(fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

/// 이번 달 요약: 다 먹은 날 · 일부 · 못 먹은 날
class _Totals extends StatelessWidget {
  const _Totals({required this.list});
  final List<DaySummary> list;

  @override
  Widget build(BuildContext context) {
    int count(DayKind k) => list.where((s) => s.kind == k).length;
    Widget box(String label, int n, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Toss.grey50, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text('$n일', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 13, color: Toss.grey600)),
            ]),
          ),
        );
    return Row(children: [
      box('다 먹음', count(DayKind.all), Toss.blue),
      const SizedBox(width: 8),
      box('일부', count(DayKind.partial), Toss.blue),
      const SizedBox(width: 8),
      box('못 먹음', count(DayKind.missed), Toss.grey700),
    ]);
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.list});
  final DateTime month;
  final List<DaySummary> list;

  @override
  Widget build(BuildContext context) {
    final today = dateString(DateTime.now());
    final lead = DateTime(month.year, month.month, 1).weekday - 1; // 월요일 시작
    final cells = <Widget>[
      for (final w in weekdayLabels)
        Center(child: Text(w, style: const TextStyle(fontSize: 13, color: Toss.grey600, fontWeight: FontWeight.w700))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (final s in list)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: s.kind == DayKind.future ? null : () => showDaySheet(context, s),
          child: Container(
            decoration: dateString(s.day) == today
                ? BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Toss.blue, width: 1.5))
                : null,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${s.day.day}', style: const TextStyle(fontSize: 13, color: Toss.grey700)),
              const SizedBox(height: 3),
              AdherenceDot(summary: s, size: 28),
            ]),
          ),
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.72, // 큰 글자에서도 잘리지 않게 세로 여유
      children: cells,
    );
  }
}
