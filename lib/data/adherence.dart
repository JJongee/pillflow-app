import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'providers.dart';
import 'repository.dart';

/// 복용 달력 — 날짜별로 다 먹음 / 일부 / 못 먹음 / 약 없음 / 진행 중(오늘)
enum DayKind { all, partial, missed, noMeds, inProgress, future }

class DaySummary {
  final DateTime day;
  final int taken;
  final int skipped;
  final int total;

  /// 아직 기록 안 한 칸 (서버 pending)
  final int pending;

  /// 서버 day_status ('NO_DRUG' 등). 없으면 숫자로 판단
  final String? dayStatus;

  DaySummary({
    required this.day,
    required this.taken,
    required this.skipped,
    required this.total,
    int? pending,
    this.dayStatus,
  }) : pending = pending ?? (total - taken - skipped);

  const DaySummary.future(this.day)
      : taken = 0,
        skipped = 0,
        total = 0,
        pending = 0,
        dayStatus = null;

  bool get isFuture => _onlyDate(day).isAfter(_onlyDate(DateTime.now()));
  bool get isToday => _onlyDate(day) == _onlyDate(DateTime.now());

  DayKind get kind {
    if (isFuture) return DayKind.future;
    if (total == 0 || dayStatus == 'NO_DRUG') return DayKind.noMeds;
    if (taken >= total) return DayKind.all;
    // 오늘은 아직 하루가 안 끝났으니 '못 먹음'이 아니라 '진행 중' (연우 10/23: 앱에서 처리)
    if (isToday && pending > 0) return DayKind.inProgress;
    if (taken == 0) return DayKind.missed;
    return DayKind.partial;
  }

  static DaySummary of(DateTime day, List<IntakeRecord> list) => DaySummary(
        day: day,
        taken: list.where((r) => r.status == IntakeStatus.taken).length,
        skipped: list.where((r) => r.status == IntakeStatus.skipped).length,
        total: list.length,
      );

  static DaySummary fromServer(DateTime day, IntakeDaySummary r) => DaySummary(
        day: day,
        taken: r.taken,
        skipped: r.skipped,
        total: r.scheduled,
        pending: r.pending,
        dayStatus: r.dayStatus,
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

/// 기간 요약 API(GET /me/intakes/summary) 한 번으로 받기. 오늘 이후는 '앞으로'
/// 요약 API가 없는 예전 서버면 날짜마다 따로 부름 (로그인 만료는 그대로 알림)
Future<List<DaySummary>> summarizeDays(PillRepository repo, List<DateTime> days) async {
  if (days.isEmpty) return const [];
  final past = days.where((d) => !DaySummary.future(d).isFuture).toList();
  Map<String, IntakeDaySummary> rows = const {};
  if (past.isNotEmpty) {
    try {
      final list = await repo.getIntakeSummary(dateString(past.first), dateString(past.last));
      rows = {for (final r in list) r.date: r};
    } on RepoException catch (e) {
      if (e.code == 'UNAUTHORIZED' || e.code == 'NETWORK') rethrow;
      return Future.wait(days.map((d) async {
        final s = DaySummary.future(d);
        if (s.isFuture) return s;
        return DaySummary.of(d, await repo.getIntakes(dateString(d)));
      }));
    }
  }
  return [
    for (final d in days)
      DaySummary.future(d).isFuture
          ? DaySummary.future(d)
          : rows[dateString(d)] == null
              ? DaySummary(day: d, taken: 0, skipped: 0, total: 0, dayStatus: 'NO_DRUG')
              : DaySummary.fromServer(d, rows[dateString(d)]!),
  ];
}

/// 키: (시작일, 끝일) 'YYYY-MM-DD'
final daySummariesProvider = FutureProvider.autoDispose.family<List<DaySummary>, (String, String)>((ref, range) {
  final from = DateTime.parse(range.$1);
  final to = DateTime.parse(range.$2);
  final days = [for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) d];
  return summarizeDays(ref.watch(repositoryProvider), days);
});

(String, String) rangeKey(List<DateTime> days) => (dateString(days.first), dateString(days.last));
