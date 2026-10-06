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
  noKnownIssue('NO_KNOWN_ISSUE', '확인된 금기 기록 없음'),
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

/// DUR 유형 코드 → 화면 이름. 서버가 새 유형을 보내도 화면이 깨지지 않도록 모르는 코드는 'DUR 주의'로 표시합니다.
String durTypeLabel(String code) => switch (code) {
      'COMBINATION' => '병용금기',
      'AGE' => '연령금기',
      'PREGNANCY' => '임부금기',
      'DOSE' => '용량주의',
      'ELDERLY' => '노인주의',
      'DUPLICATE' || 'EFFICACY_DUPLICATE' || 'EFFICACY' => '효능군중복 주의',
      'DURATION' => '투여기간주의',
      _ => 'DUR 주의',
    };

enum FindingType { combination, age, other }

class DurFinding {
  final FindingType type;

  /// 서버가 보낸 원래 유형 코드 (예: COMBINATION, AGE, 이후 ELDERLY 등)
  final String typeCode;
  final List<String> itemSeqs;
  final List<String> ingredients;
  final String detail;
  final String? conditionNote; // 병용금기 파일의 '비고' (예: 48시간 이내 병용금기)
  final String? noticeNo;
  final String? noticeDate;

  const DurFinding({
    required this.type,
    this.typeCode = '',
    required this.itemSeqs,
    required this.ingredients,
    required this.detail,
    this.conditionNote,
    this.noticeNo,
    this.noticeDate,
  });

  /// 유형 코드 (생성자에서 안 주면 type 으로 추정)
  String get code => typeCode.isNotEmpty
      ? typeCode
      : switch (type) {
          FindingType.age => 'AGE',
          FindingType.combination => 'COMBINATION',
          FindingType.other => 'OTHER',
        };

  String get label => durTypeLabel(code);

  factory DurFinding.fromJson(Map<String, dynamic> j) {
    final code = (_str(j['type']) ?? 'COMBINATION').toUpperCase();
    return DurFinding(
        type: switch (code) {
          'COMBINATION' => FindingType.combination,
          'AGE' => FindingType.age,
          _ => FindingType.other,
        },
        typeCode: code,
        itemSeqs: (j['item_seqs'] as List? ?? const []).map((e) => e.toString()).toList(),
        ingredients: (j['ingredients'] as List? ?? const []).map((e) => e.toString()).toList(),
        detail: _str(j['detail']) ?? '',
        conditionNote: _str(j['condition_note']),
        noticeNo: _str(j['notice_no']),
        noticeDate: _str(j['notice_date']),
      );
  }
}

/// 참고 정보(임부금기·용량주의 등)의 기준 상태
enum CautionStatus {
  confirmed('CONFIRMED', '기준 확인됨'),
  pending('PENDING', '기준 확인 중'),
  conflict('CONFLICT', '기준이 서로 달라요');

  final String code;
  final String label;
  const CautionStatus(this.code, this.label);

  /// 모르는 값은 '확인 중'으로 취급 (절대 '괜찮음'으로 보이지 않게)
  static CautionStatus fromCode(String? c) =>
      CautionStatus.values.firstWhere((e) => e.code == c, orElse: () => CautionStatus.pending);
}

/// DUR 참고 정보 (임부금기·용량주의). 판정(verdict)에는 들어가지 않습니다.
class DurCaution {
  final String typeCode; // PREGNANCY / DOSE / ...
  final List<String> itemSeqs;
  final List<String> ingredients;
  final CautionStatus status;
  final String? grade;
  final String detail;
  final String? conditionNote;
  final String? noticeDate;

  const DurCaution({
    required this.typeCode,
    required this.itemSeqs,
    required this.ingredients,
    required this.status,
    this.grade,
    required this.detail,
    this.conditionNote,
    this.noticeDate,
  });

  String get label => durTypeLabel(typeCode);

  /// 화면 보조 문구 (서버 문서 4-1 제안)
  String get hint => switch (typeCode) {
        'PREGNANCY' => '임신 중이라면 금기예요',
        'DOSE' => '하루 최대량을 넘지 않게 주의하세요',
        _ => '복용 전에 확인해 주세요',
      };

  factory DurCaution.fromJson(Map<String, dynamic> j) => DurCaution(
        typeCode: (_str(j['type']) ?? '').toUpperCase(),
        itemSeqs: (j['item_seqs'] as List? ?? const []).map((e) => e.toString()).toList(),
        ingredients: (j['ingredients'] as List? ?? const []).map((e) => e.toString()).toList(),
        status: CautionStatus.fromCode(_str(j['status'])),
        grade: _str(j['grade']),
        detail: _str(j['detail']) ?? '',
        conditionNote: _str(j['condition_note']),
        noticeDate: _str(j['notice_date']),
      );
}

class DurCheckResult {
  final String? dataVersion;
  final String? checkedAt;
  final bool ageUnknown;
  final List<DurDrugVerdict> drugs;
  final List<DurFinding> findings;
  final List<DurCaution> cautions;

  const DurCheckResult({
    this.dataVersion,
    this.checkedAt,
    required this.ageUnknown,
    required this.drugs,
    required this.findings,
    this.cautions = const [],
  });

  factory DurCheckResult.fromJson(Map<String, dynamic> j) => DurCheckResult(
        dataVersion: _str(j['data_version']),
        checkedAt: _str(j['checked_at']),
        ageUnknown: j['age_unknown'] == true,
        drugs: (j['drugs'] as List? ?? const []).map((e) => DurDrugVerdict.fromJson(e as Map<String, dynamic>)).toList(),
        findings:
            (j['findings'] as List? ?? const []).map((e) => DurFinding.fromJson(e as Map<String, dynamic>)).toList(),
        cautions: (j['cautions'] as List? ?? const [])
            .map((e) => DurCaution.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------- 자동 시간표 제안 (POST /me/schedules/suggest) ----------------

enum SuggestConfidence {
  high('HIGH', '추천'),
  confirm('CONFIRM', '확인 필요'),
  none('NONE', '직접 입력');

  final String code;
  final String label;
  const SuggestConfidence(this.code, this.label);

  static SuggestConfidence fromCode(String? c) =>
      SuggestConfidence.values.firstWhere((e) => e.code == c, orElse: () => SuggestConfidence.none);
}

class SuggestSlot {
  final String time; // HH:mm
  final MealRelation mealRelation;
  const SuggestSlot({required this.time, required this.mealRelation});

  factory SuggestSlot.fromJson(Map<String, dynamic> j) => SuggestSlot(
        time: j['time'] as String,
        mealRelation: MealRelation.fromCode(j['meal_relation'] as String?),
      );
}

class ScheduleSuggestion {
  final int userDrugId;
  final String itemSeq;
  final String itemName;
  final SuggestConfidence confidence;
  final int? timesPerDay;
  final List<SuggestSlot> slots;
  final String? basis; // 근거 용법 원문
  final List<String> warnings;

  const ScheduleSuggestion({
    required this.userDrugId,
    required this.itemSeq,
    required this.itemName,
    required this.confidence,
    this.timesPerDay,
    required this.slots,
    this.basis,
    this.warnings = const [],
  });

  factory ScheduleSuggestion.fromJson(Map<String, dynamic> j) => ScheduleSuggestion(
        userDrugId: j['user_drug_id'] as int,
        itemSeq: j['item_seq'].toString(),
        itemName: j['item_name'] as String,
        confidence: SuggestConfidence.fromCode(j['confidence'] as String?),
        timesPerDay: j['times_per_day'] as int?,
        slots: (j['slots'] as List? ?? const [])
            .map((e) => SuggestSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
        basis: _str(j['basis']),
        warnings: (j['warnings'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
}

class ScheduleSuggestResult {
  final List<ScheduleSuggestion> suggestions;
  final List<DurFinding> durFindings;
  final List<String> notes;

  const ScheduleSuggestResult({required this.suggestions, this.durFindings = const [], this.notes = const []});

  factory ScheduleSuggestResult.fromJson(Map<String, dynamic> j) => ScheduleSuggestResult(
        suggestions: (j['suggestions'] as List? ?? const [])
            .map((e) => ScheduleSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        durFindings: (j['dur_findings'] as List? ?? const [])
            .map((e) => DurFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: (j['notes'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
}

class Paged<T> {
  final List<T> items;
  final int page;
  final int size;
  final int total;
  const Paged({required this.items, required this.page, required this.size, required this.total});
}
