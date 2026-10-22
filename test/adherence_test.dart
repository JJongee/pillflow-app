import 'package:flutter_test/flutter_test.dart';
import 'package:pillflow/data/adherence.dart';
import 'package:pillflow/models/models.dart';

IntakeRecord _r(IntakeStatus s) =>
    IntakeRecord(scheduleId: 1, date: '2026-10-20', time: '08:00', itemName: '타이레놀', status: s);

void main() {
  final past = DateTime(2026, 10, 20);

  test('복용 달력: 날짜별 상태 (다 먹음·일부·못 먹음·약 없음)', () {
    expect(DaySummary.of(past, [_r(IntakeStatus.taken), _r(IntakeStatus.taken)]).kind, DayKind.all);
    expect(DaySummary.of(past, [_r(IntakeStatus.taken), _r(IntakeStatus.pending)]).kind, DayKind.partial);
    // 건너뛴 약은 먹은 것으로 세지 않음
    expect(DaySummary.of(past, [_r(IntakeStatus.skipped)]).kind, DayKind.missed);
    expect(DaySummary.of(past, []).kind, DayKind.noMeds);
    final p = DaySummary.of(past, [_r(IntakeStatus.taken), _r(IntakeStatus.skipped), _r(IntakeStatus.pending)]);
    expect((p.taken, p.skipped, p.total), (1, 1, 3));
  });

  test('복용 달력: 앞으로의 날은 비워 둔다', () {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(DaySummary.future(tomorrow).kind, DayKind.future);
  });

  test('복용 달력: 주는 월~일, 달은 1일~말일', () {
    final w = weekOf(DateTime(2026, 10, 22)); // 목요일
    expect(w.length, 7);
    expect(w.first, DateTime(2026, 10, 19)); // 월
    expect(w.last, DateTime(2026, 10, 25)); // 일
    expect(monthOf(2026, 2).length, 28);
    expect(monthOf(2026, 10).last, DateTime(2026, 10, 31));
    expect(rangeKey(w), ('2026-10-19', '2026-10-25'));
  });
}
