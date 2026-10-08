import '../models/models.dart';

/// 화면은 이 인터페이스만 봅니다.
/// 목업([MockRepository])과 실제 서버([ApiRepository])는 AppConfig.useMock 으로 바뀝니다.
abstract class PillRepository {
  // 0. 인증 — 성공하면 access token 을 돌려줍니다.
  Future<String> login(String email, String password);
  Future<void> signup(String email, String password);

  // 1. 검색·상세
  Future<Paged<DrugSummary>> searchDrugs(String query, {int page = 1, int size = 20});
  Future<DrugDetail> getDrug(String itemSeq);

  // 2. 내 약
  Future<List<UserDrug>> getMyDrugs();
  Future<UserDrug> addMyDrug(String itemSeq, {String? memo});
  Future<UserDrug> updateMyDrug(int id, {String? memo});
  Future<void> deleteMyDrug(int id);

  // 3. 시간표 (사용자 지정)
  Future<List<ScheduleItem>> getSchedules();
  Future<ScheduleItem> addSchedule({
    required int userDrugId,
    required String time,
    required MealRelation mealRelation,
    String? doseText,
  });
  Future<ScheduleItem> updateSchedule(
    int id, {
    required String time,
    required MealRelation mealRelation,
    String? doseText,
  });
  Future<void> deleteSchedule(int id);

  /// 자동 시간표 제안 (서버는 저장하지 않음 → 고른 칸만 addSchedule 로 저장)
  Future<ScheduleSuggestResult> suggestSchedules({List<int>? userDrugIds});

  // 4. 복용 기록
  Future<List<IntakeRecord>> getIntakes(String date);
  Future<void> setIntake({required int scheduleId, required String date, required IntakeStatus status});

  // 5. 프로필
  Future<Profile> getProfile();
  Future<void> setBirthDate(DateTime date);
  Future<void> setBirthYear(int? year);

  // 6. DUR
  Future<DurCheckResult> checkDur({List<String>? itemSeqs});
}

/// 서버/목업 공통 에러. 화면에서는 message만 보여주면 됩니다.
class RepoException implements Exception {
  final String message;
  final String? code;
  RepoException(this.message, {this.code});
  @override
  String toString() => message;
}
