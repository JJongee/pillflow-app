import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'providers.dart';
import 'repository.dart';

/// 복용 달력 — 날짜별로 다 먹음 / 일부 / 못 먹음 / 약 없음
enum DayKind { all, partial, missed, noMeds, future }

class DaySummary {
  final DateTime day;
  final int taken;
  final int skipped;
  final int total;
  final List<IntakeRecord> records;

  const DaySummary({
    required this.day,
    required this.taken,
    required this.skipped,
    required this.total,
    this.records = const [],
  });

  const DaySummary.future(this.day)
      : taken = 0,
        skipped = 0,
        total = 0,
        records = const [];

  bool get isFuture => _onlyDate(day).isAfter(_onlyDate(DateTime.now()));

  DayKind get kind {
    if (isFuture) return DayKind.future;
    if (total == 0) return DayKind.noMeds;
    if (taken >= total) return DayKind.all;
    if (taken == 0) return DayKind.missed;
    return DayKind.partial;
  }

  static DaySummary of(DateTime day, List<IntakeRecord> list) => DaySummary(
        day: day,
        taken: list.where((r) => r.status == IntakeStatus.taken).length,
        skipped: list.where((r) => r.status == IntakeStatus.skipped).length,
        total: list.length,
        records: list,
      );
}

DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);

/// 그 주의 월요일 ~ 일요일
List<DateTime> weekOf(DateTime d) {
  final monday = _onlyDate(d).subtract(Duration(days: d.weekday - 1));
  return [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
}

/// 그 달의 1일 ~ 말일
List<DateTime> monthOf(int year, int month) {
  final last = DateTime(year, month + 1, 0).day;
  return [for (var i = 1; i <= last; i++) DateTime(year, month, i)];
}

const weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// 지금 서버는 하루씩만 복용 기록을 줘서 날짜마다 따로 부름 (오늘 이후는 부르지 않음)
/// TODO: 서버에 기간 조회 API(GET /me/intakes?from=&to=)가 생기면 한 번에 받기
Future<List<DaySummary>> summarizeDays(PillRepository repo, List<DateTime> days) => Future.wait(days.map((d) async {
      final s = DaySummary.future(d);
      if (s.isFuture) return s;
      return DaySummary.of(d, await repo.getIntakes(dateString(d)));
    }));

/// 키: (시작일, 끝일) 'YYYY-MM-DD'
final daySummariesProvider = FutureProvider.autoDispose.family<List<DaySummary>, (String, String)>((ref, range) {
  final from = DateTime.parse(range.$1);
  final to = DateTime.parse(range.$2);
  final days = [for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) d];
  return summarizeDays(ref.watch(repositoryProvider), days);
});

(String, String) rangeKey(List<DateTime> days) => (dateString(days.first), dateString(days.last));
