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

/// 2단계 유형(서버 type 값 확정 전이라 비슷한 이름도 받아 둠)
enum DurKind { pregnancy, dose, elderly, efficacyDuplicate, duration, other }

DurKind durKindOf(String code) => switch (code) {
      'PREGNANCY' => DurKind.pregnancy,
      'DOSE' => DurKind.dose,
      'ELDERLY' || 'SENIOR' || 'OLD_AGE' => DurKind.elderly,
      'DUPLICATE' || 'EFFICACY_DUPLICATE' || 'EFFICACY' || 'THERAPEUTIC_DUPLICATE' => DurKind.efficacyDuplicate,
      'DURATION' || 'PERIOD' => DurKind.duration,
      _ => DurKind.other,
    };

/// DUR 유형 코드 → 화면 이름. 서버가 새 유형을 보내도 화면이 깨지지 않도록 모르는 코드는 'DUR 주의'로 표시합니다.
String durTypeLabel(String code) => switch (code) {
      'COMBINATION' => '병용금기',
      'AGE' => '연령금기',
      'PREGNANCY' => '임부금기',
      'DOSE' => '용량주의',
      'ELDERLY' || 'SENIOR' || 'OLD_AGE' => '노인주의',
      'DUPLICATE' || 'EFFICACY_DUPLICATE' || 'EFFICACY' || 'THERAPEUTIC_DUPLICATE' => '효능군중복주의',
      'DURATION' || 'PERIOD' => '투여기간주의',
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
  confirmed('CONFIRMED', '기준 연결 확인'),
  pending('PENDING', '기준 확인 중'),
  conflict('CONFLICT', '기준이 서로 달라요');

  final String code;
  final String label;
  const CautionStatus(this.code, this.label);

  /// 모르는 값은 '확인 중'으로 취급 (절대 '괜찮음'으로 보이지 않게)
  static CautionStatus fromCode(String? c) =>
      CautionStatus.values.firstWhere((e) => e.code == c, orElse: () => CautionStatus.pending);
}

/// 참고 정보 카드에 줄로 보여 줄 항목 (서버 cautions[].info). 서버는 값이 있는 칸만 보냄
class InfoLine {
  final String label;
  final String value;
  const InfoLine(this.label, this.value);

  /// 형식이 바뀌어도 깨지지 않게 여러 모양을 받음:
  ///  {"성분": "…", "제형": "…"} / [{"label": "성분", "value": "…"}] / [["성분", "…"]] / ["성분: …"]
  static List<InfoLine> parse(dynamic raw) {
    final out = <InfoLine>[];
    void add(dynamic k, dynamic v) {
      final key = _str(k);
      final val = v is List ? _str(v.map((e) => e.toString()).join(', ')) : _str(v);
      if (key != null && val != null) out.add(InfoLine(key, val));
    }

    if (raw is Map) {
      raw.forEach(add);
    } else if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          add(e['label'] ?? e['name'] ?? e['key'] ?? e['title'], e['value'] ?? e['text']);
        } else if (e is List && e.length >= 2) {
          add(e[0], e[1]);
        } else if (e is String && e.contains(':')) {
          final i = e.indexOf(':');
          add(e.substring(0, i), e.substring(i + 1));
        }
      }
    }
    return out;
  }
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

  /// 효능군중복주의: 효능군·계열 (서버 필드 이름 확정 전)
  final String? efficacyGroup;
  final String? series;

  /// 투여기간주의: 기간 기준 원문. 조건마다 다를 수 있어 숫자로 줄이지 않고 그대로 보여 줌
  final String? periodText;

  /// 서버가 정리해 준 표시용 줄 (있으면 이걸 우선 그림)
  final List<InfoLine> info;

  const DurCaution({
    required this.typeCode,
    required this.itemSeqs,
    required this.ingredients,
    required this.status,
    this.grade,
    required this.detail,
    this.conditionNote,
    this.noticeDate,
    this.efficacyGroup,
    this.series,
    this.periodText,
    this.info = const [],
  });

  String get label => durTypeLabel(typeCode);
  DurKind get kind => durKindOf(typeCode);

  /// 화면 보조 문구 (서버 문서 4-1 제안)
  /// 사용자에게 해당된다고 단정하지 않는 문구만 씀
  String get hint => switch (kind) {
        DurKind.pregnancy => '임신 중이라면 금기예요',
        DurKind.dose => '하루 최대량을 넘지 않게 주의하세요',
        DurKind.elderly => '고령자가 먹을 때 주의가 필요한 약으로 연결돼 있어요',
        DurKind.efficacyDuplicate => '같은 효능군의 약이 함께 있어요. 실제 중복 복용인지는 약사와 확인해 주세요',
        DurKind.duration => '오래 계속 먹을 때 주의가 필요한 약이에요. 기간 기준은 조건에 따라 달라요',
        DurKind.other => '복용 전에 확인해 주세요',
      };

  /// 서버 필드 이름이 정해지기 전이라 후보 이름을 차례로 확인
  static String? _first(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = _str(j[k]);
      if (v != null) return v;
    }
    return null;
  }

  factory DurCaution.fromJson(Map<String, dynamic> j) => DurCaution(
        typeCode: (_str(j['type']) ?? '').toUpperCase(),
        itemSeqs: (j['item_seqs'] as List? ?? const []).map((e) => e.toString()).toList(),
        ingredients: (j['ingredients'] as List? ?? const []).map((e) => e.toString()).toList(),
        status: CautionStatus.fromCode(_str(j['status'])),
        grade: _str(j['grade']),
        detail: _str(j['detail']) ?? '',
        conditionNote: _str(j['condition_note']),
        noticeDate: _str(j['notice_date']),
        efficacyGroup: _first(j, const ['efficacy_group', 'efficacy_class', 'group']),
        series: _first(j, const ['series', 'drug_class', 'class_name']),
        periodText: _first(j, const ['period_text', 'duration_text', 'period', 'duration']),
        info: InfoLine.parse(j['info']),
      );

  /// findings 로 온 2단계 유형(노인주의 등)을 참고 정보로 옮길 때 사용.
  /// 상태 정보가 없으므로 '기준 확인 중'으로 둠
  factory DurCaution.fromFinding(DurFinding f) => DurCaution(
        typeCode: f.code,
        itemSeqs: f.itemSeqs,
        ingredients: f.ingredients,
        status: CautionStatus.pending,
        detail: f.detail,
        conditionNote: f.conditionNote,
        noticeDate: f.noticeDate,
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

  /// 판정에 들어가는 금기 (병용금기·연령금기)
  List<DurFinding> get contraindications => findings.where((f) => f.type != FindingType.other).toList();

  /// 화면의 '참고 정보': cautions + findings로 온 2단계 유형
  /// (서버가 노인주의 등을 findings에 넣어도 금기(빨강)로 보이지 않게)
  List<DurCaution> get allCautions => [
        ...cautions,
        ...findings.where((f) => f.type == FindingType.other).map(DurCaution.fromFinding),
      ];

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

  /// 프로필에 생년월일·태어난 해가 있는지 (null = 서버가 안 보냄)
  final bool? ageKnown;

  const ScheduleSuggestResult({
    required this.suggestions,
    this.durFindings = const [],
    this.notes = const [],
    this.ageKnown,
  });

  factory ScheduleSuggestResult.fromJson(Map<String, dynamic> j) => ScheduleSuggestResult(
        suggestions: (j['suggestions'] as List? ?? const [])
            .map((e) => ScheduleSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        durFindings: (j['dur_findings'] as List? ?? const [])
            .map((e) => DurFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: (j['notes'] as List? ?? const []).map((e) => e.toString()).toList(),
        ageKnown: j['age_known'] is bool ? j['age_known'] as bool : null,
      );
}

/// 내 정보 (GET /me/profile). 생년월일이 있으면 그걸 우선 사용
class Profile {
  final int? birthYear;
  final DateTime? birthDate;
  const Profile({this.birthYear, this.birthDate});

  bool get hasAge => birthYear != null || birthDate != null;

  /// 화면 표시: 1958.03.15 / 1958년생 / null
  String? get display {
    final d = birthDate;
    if (d != null) return '${d.year}.${_two(d.month)}.${_two(d.day)}';
    return birthYear == null ? null : '$birthYear년생';
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        birthYear: j['birth_year'] is int ? j['birth_year'] as int : int.tryParse('${j['birth_year']}'),
        birthDate: DateTime.tryParse(_str(j['birth_date']) ?? ''),
      );
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 서버 형식 YYYY-MM-DD
String dateString(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

class Paged<T> {
  final List<T> items;
  final int page;
  final int size;
  final int total;
  const Paged({required this.items, required this.page, required this.size, required this.total});
}
