import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/adherence.dart';
import '../models/models.dart';
import '../screens/adherence_calendar_screen.dart';

/// 하루 표시 동그라미
///  다 먹음: 진한 파랑 + 체크 / 일부: 먹은 비율만큼 채워지는 파란 고리 / 못 먹음: 회색 테두리 / 약 없음: 작은 점 / 앞으로: 비움
/// 빨강은 '금기' 경고에만 쓰므로 여기서는 쓰지 않음
class AdherenceDot extends StatelessWidget {
  const AdherenceDot({super.key, required this.summary, this.size = 30});
  final DaySummary summary;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    switch (s.kind) {
      case DayKind.all:
        return _circle(Toss.blue, null, Icon(Icons.check, size: size * 0.6, color: Colors.white));
      case DayKind.partial:
        // 먹은 비율만큼 파란 고리가 채워짐 (예: 3개 중 2개 → 2/3 바퀴)
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _RingPainter(s.taken / s.total)),
        );
      case DayKind.missed:
        return _circle(Colors.white, Toss.grey400, null);
      case DayKind.noMeds:
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Toss.grey300),
            ),
          ),
        );
      case DayKind.future:
        return SizedBox(width: size, height: size);
    }
  }

  Widget _circle(Color fill, Color? border, Widget? child) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: border == null ? null : Border.all(color: border, width: 2),
        ),
        child: child == null ? null : Center(child: child),
      );
}

/// 범례 한 줄
class AdherenceLegend extends StatelessWidget {
  const AdherenceLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13);
    Widget item(DayKind k, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          AdherenceDot(summary: _sample(k), size: 18),
          const SizedBox(width: 4),
          Text(label, style: t),
        ]);
    return Wrap(spacing: 14, runSpacing: 6, children: [
      item(DayKind.all, '다 먹음'),
      item(DayKind.partial, '일부'),
      item(DayKind.missed, '못 먹음'),
      item(DayKind.noMeds, '약 없음'),
    ]);
  }

  static DaySummary _sample(DayKind k) {
    final past = DateTime(2000);
    return switch (k) {
      DayKind.all => DaySummary(day: past, taken: 1, skipped: 0, total: 1),
      DayKind.partial => DaySummary(day: past, taken: 1, skipped: 0, total: 2),
      DayKind.missed => DaySummary(day: past, taken: 0, skipped: 0, total: 1),
      _ => DaySummary(day: past, taken: 0, skipped: 0, total: 0),
    };
  }
}

/// 오늘 화면 맨 위: 이번 주 월~일 복용 상태 + 달력 보기
class WeekStrip extends ConsumerWidget {
  const WeekStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = weekOf(DateTime.now());
    final value = ref.watch(daySummariesProvider(rangeKey(days)));
    final today = dateString(DateTime.now());
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 4),
            Text('이번 주 복용', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdherenceCalendarScreen())),
              child: const Text('달력 보기 ›'),
            ),
          ]),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayCell(
                    day: days[i],
                    label: weekdayLabels[i],
                    isToday: dateString(days[i]) == today,
                    summary: value.valueOrNull?[i],
                  ),
                ),
            ],
          ),
          if (value.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('복용 기록을 불러오지 못했어요.', style: t.bodySmall),
            ),
        ]),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.label, required this.isToday, this.summary});
  final DateTime day;
  final String label;
  final bool isToday;
  final DaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: s == null || s.kind == DayKind.future ? null : () => showDaySheet(context, s),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: isToday
            ? BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Toss.blue, width: 1.5))
            : null,
        child: Column(children: [
          Text(label,
              style: TextStyle(
                fontSize: 13,
                color: isToday ? Toss.blue : Toss.grey600,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              )),
          const SizedBox(height: 2),
          Text('${day.day}', style: const TextStyle(fontSize: 13, color: Toss.grey600)),
          const SizedBox(height: 6),
          s == null
              ? const SizedBox(width: 30, height: 30)
              : AdherenceDot(summary: s),
        ]),
      ),
    );
  }
}

/// 날짜를 누르면: 그날 먹은 약 / 건너뛴 약 / 못 먹은 약
Future<void> showDaySheet(BuildContext context, DaySummary s) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final t = Theme.of(context).textTheme;
        final d = s.day;
        final title = '${d.month}월 ${d.day}일 (${weekdayLabels[d.weekday - 1]})';
        final sorted = [...s.records]..sort((a, b) => a.time.compareTo(b.time));
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
              Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                s.total == 0 ? '이날은 먹을 약이 없었어요.' : '${s.taken} / ${s.total} 복용',
                style: t.bodyLarge?.copyWith(color: Toss.grey600),
              ),
              const SizedBox(height: 12),
              for (final r in sorted)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    SizedBox(width: 56, child: Text(r.time, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    Expanded(child: Text(r.itemName, style: t.bodyLarge)),
                    const SizedBox(width: 8),
                    _StatusChip(status: r.status),
                  ]),
                ),
            ]),
          ),
        );
      },
    );

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final IntakeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      IntakeStatus.taken => ('먹었어요', Colors.white, Toss.blue),
      IntakeStatus.skipped => ('건너뜀', Toss.grey700, Toss.grey100),
      IntakeStatus.pending => ('기록 없음', Toss.grey600, Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: status == IntakeStatus.pending ? Border.all(color: Toss.grey300) : null,
      ),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

/// 일부 먹은 날: 연한 파랑 바탕 + 회색 고리 위에 먹은 비율만큼 진한 파랑 고리
class _RingPainter extends CustomPainter {
  _RingPainter(this.ratio);
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Offset.zero & size;
    final inner = rect.deflate(stroke / 2);
    canvas.drawCircle(rect.center, size.width / 2, Paint()..color = Toss.blue50);
    canvas.drawArc(inner, 0, 6.2832, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Toss.grey200);
    canvas.drawArc(inner, -1.5708, 6.2832 * ratio.clamp(0.0, 1.0), false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = Toss.blue);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ratio != ratio;
}
