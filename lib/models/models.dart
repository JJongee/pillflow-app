// API 초안(docs/api_contract.md)과 1:1로 맞춘 모델입니다.
// 서버 응답 형식이 바뀌면 fromJson만 고치면 됩니다.

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// 검색 결과 한 줄
class DrugSummary {
  final String itemSeq;
  final String itemName;
  final String? entpName;
  final String? imageUrl;
  final String? source;

  const DrugSummary({
    required this.itemSeq,
    required this.itemName,
    this.entpName,
    this.imageUrl,
    this.source,
  });

  factory DrugSummary.fromJson(Map<String, dynamic> j) => DrugSummary(
        itemSeq: j['item_seq'].toString(),
        itemName: j['item_name'] as String,
        entpName: _str(j['entp_name']),
        imageUrl: _str(j['image_url']),
        source: _str(j['source']),
      );
}

/// 약 상세 (e약은요 필드)
class DrugDetail extends DrugSummary {
  final String? efficacy;
  final String? useMethod;
  final String? warning;
  final String? caution;
  final String? interaction;
  final String? sideEffect;
  final String? storage;
  final String? openDate;
  final String? updateDate;

  const DrugDetail({
    required super.itemSeq,
    required super.itemName,
    super.entpName,
    super.imageUrl,
    super.source,
    this.efficacy,
    this.useMethod,
    this.warning,
    this.caution,
    this.interaction,
    this.sideEffect,
    this.storage,
    this.openDate,
    this.updateDate,
  });

  factory DrugDetail.fromJson(Map<String, dynamic> j) => DrugDetail(
        itemSeq: j['item_seq'].toString(),
        itemName: j['item_name'] as String,
        entpName: _str(j['entp_name']),
        imageUrl: _str(j['image_url']),
        source: _str(j['source']),
        efficacy: _str(j['efficacy']),
        useMethod: _str(j['use_method']),
        warning: _str(j['warning']),
        caution: _str(j['caution']),
        interaction: _str(j['interaction']),
        sideEffect: _str(j['side_effect']),
        storage: _str(j['storage']),
        openDate: _str(j['open_date']),
        updateDate: _str(j['update_date']),
      );
}

/// 내가 등록한 약
class UserDrug {
  final int id;
  final String itemSeq;
  final String itemName;
  final String? entpName;
  final String? imageUrl;
  final String? memo;
  final String? createdAt;

  const UserDrug({
    required this.id,
    required this.itemSeq,
    required this.itemName,
    this.entpName,
    this.imageUrl,
    this.memo,
    this.createdAt,
  });

  factory UserDrug.fromJson(Map<String, dynamic> j) => UserDrug(
        id: j['id'] as int,
        itemSeq: j['item_seq'].toString(),
        itemName: j['item_name'] as String,
        entpName: _str(j['entp_name']),
        imageUrl: _str(j['image_url']),
        memo: _str(j['memo']),
        createdAt: _str(j['created_at']),
      );
}

enum MealRelation {
  before('BEFORE', '식전'),
  after('AFTER', '식후'),
  empty('EMPTY', '공복'),
  none('NONE', '상관없음');

  final String code;
  final String label;
  const MealRelation(this.code, this.label);

  static MealRelation fromCode(String? c) =>
      MealRelation.values.firstWhere((e) => e.code == c, orElse: () => MealRelation.none);
}

/// 사용자가 직접 지정한 복용 시간 한 칸
class ScheduleItem {
  final int id;
  final int userDrugId;
  final String itemName;
  final String time; // HH:mm
  final MealRelation mealRelation;
  final String? doseText;

  const ScheduleItem({
    required this.id,
    required this.userDrugId,
    required this.itemName,
    required this.time,
    required this.mealRelation,
    this.doseText,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        id: j['id'] as int,
        userDrugId: j['user_drug_id'] as int,
        itemName: j['item_name'] as String,
        time: j['time'] as String,
        mealRelation: MealRelation.fromCode(j['meal_relation'] as String?),
        doseText: _str(j['dose_text']),
      );
}

enum IntakeStatus {
  taken('TAKEN', '먹었어요'),
  skipped('SKIPPED', '건너뜀'),
  pending('PENDING', '아직');

  final String code;
  final String label;
  const IntakeStatus(this.code, this.label);

  static IntakeStatus fromCode(String? c) =>
      IntakeStatus.values.firstWhere((e) => e.code == c, orElse: () => IntakeStatus.pending);
}

/// 하루치 복용 기록 한 줄
class IntakeRecord {
  final int scheduleId;
  final String date; // YYYY-MM-DD
  final String time;
  final String itemName;
  final IntakeStatus status;
  final String? recordedAt;

  const IntakeRecord({
    required this.scheduleId,
    required this.date,
    required this.time,
    required this.itemName,
    required this.status,
    this.recordedAt,
  });

  factory IntakeRecord.fromJson(Map<String, dynamic> j) => IntakeRecord(
        scheduleId: j['schedule_id'] as int,
        date: j['date'] as String,
        time: j['time'] as String,
        itemName: j['item_name'] as String,
        status: IntakeStatus.fromCode(j['status'] as String?),
        recordedAt: _str(j['recorded_at']),
      );
}

/// DUR 판정. 데이터에 없는 약은 절대 "안전"이 아니라 [undetermined] 입니다.
enum Verdict {
  contraindicated('CONTRAINDICATED', '함께 복용 금기'),
  noKnownIssue('NO_KNOWN_ISSUE', '확인된 금기 없음'),
  undetermined('UNDETERMINED', '판정 불가');

  final String code;
  final String label;
  const Verdict(this.code, this.label);

  static Verdict fromCode(String? c) =>
      Verdict.values.firstWhere((e) => e.code == c, orElse: () => Verdict.undetermined);
}

class DurDrugVerdict {
  final String itemSeq;
  final String itemName;
  final Verdict verdict;

  const DurDrugVerdict({required this.itemSeq, required this.itemName, required this.verdict});

  factory DurDrugVerdict.fromJson(Map<String, dynamic> j) => DurDrugVerdict(
        itemSeq: j['item_seq'].toString(),
        itemName: j['item_name'] as String,
        verdict: Verdict.fromCode(j['verdict'] as String?),
      );
}

enum FindingType { combination, age }

class DurFinding {
  final FindingType type;
  final List<String> itemSeqs;
  final List<String> ingredients;
  final String detail;
  final String? conditionNote; // 병용금기 파일의 '비고' (예: 48시간 이내 병용금기)
  final String? noticeNo;
  final String? noticeDate;

  const DurFinding({
    required this.type,
    required this.itemSeqs,
    required this.ingredients,
    required this.detail,
    this.conditionNote,
    this.noticeNo,
    this.noticeDate,
  });

  factory DurFinding.fromJson(Map<String, dynamic> j) => DurFinding(
        type: j['type'] == 'AGE' ? FindingType.age : FindingType.combination,
        itemSeqs: (j['item_seqs'] as List).map((e) => e.toString()).toList(),
        ingredients: (j['ingredients'] as List? ?? const []).map((e) => e.toString()).toList(),
        detail: j['detail'] as String,
        conditionNote: _str(j['condition_note']),
        noticeNo: _str(j['notice_no']),
        noticeDate: _str(j['notice_date']),
      );
}

class DurCheckResult {
  final String? dataVersion;
  final String? checkedAt;
  final bool ageUnknown;
  final List<DurDrugVerdict> drugs;
  final List<DurFinding> findings;

  const DurCheckResult({
    this.dataVersion,
    this.checkedAt,
    required this.ageUnknown,
    required this.drugs,
    required this.findings,
  });

  factory DurCheckResult.fromJson(Map<String, dynamic> j) => DurCheckResult(
        dataVersion: _str(j['data_version']),
        checkedAt: _str(j['checked_at']),
        ageUnknown: j['age_unknown'] == true,
        drugs: (j['drugs'] as List).map((e) => DurDrugVerdict.fromJson(e as Map<String, dynamic>)).toList(),
        findings:
            (j['findings'] as List).map((e) => DurFinding.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class Paged<T> {
  final List<T> items;
  final int page;
  final int size;
  final int total;
  const Paged({required this.items, required this.page, required this.size, required this.total});
}
