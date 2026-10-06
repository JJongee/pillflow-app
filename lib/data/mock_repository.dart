import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';
import 'repository.dart';

/// 12MB JSON 을 메인 스레드 밖에서 파싱 (화면 버벅임 방지)
List<Map<String, dynamic>> _parseDrugs(String raw) =>
    List<Map<String, dynamic>>.from(jsonDecode(raw) as List);

/// 검색용 정규화: 띄어쓰기 무시, 영문 대소문자 무시
String normalizeForSearch(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 서버 없이 화면을 개발하기 위한 목업.
/// - assets/mock/drugs.json : all_drugs_data.csv(e약은요) 전체 4,741품목 + DUR 전용 품목 1개
///   (원본 4,758행 중 이미지만 다른 중복 17행은 합침, 날짜는 YYYY-MM-DD 로 정규화)
/// - assets/mock/dur_rules.json : 병용금기·연령금기 실제 행에서 뽑은 규칙
/// 앱을 껐다 켜면 내 약/시간표/기록은 초기화됩니다(메모리 저장).
class MockRepository implements PillRepository {
  List<Map<String, dynamic>> _drugs = const [];
  Map<String, Map<String, dynamic>> _bySeq = const {};
  List<String> _searchKeys = const []; // _drugs 와 같은 순서의 정규화된 이름
  Map<String, dynamic> _rules = const {};
  Future<void>? _loading;

  final List<UserDrug> _myDrugs = [];
  final List<ScheduleItem> _schedules = [];
  final Map<String, IntakeStatus> _intakes = {}; // key: '$scheduleId|$date'
  final Map<String, String> _recordedAt = {};
  int? _birthYear;
  int _nextId = 1;

  /// 실제 네트워크처럼 로딩 상태가 보이도록 약간 지연
  Future<void> _delay() => Future.delayed(const Duration(milliseconds: 350));

  /// 처음 한 번만 읽습니다. 동시에 여러 화면이 불러도 한 번만 파싱. 실패하면 다음에 다시 시도.
  Future<void> _load() async {
    try {
      await (_loading ??= _doLoad());
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> _doLoad() async {
    final raw = await rootBundle.loadString('assets/mock/drugs.json');
    final drugs = await compute(_parseDrugs, raw);
    _rules = jsonDecode(await rootBundle.loadString('assets/mock/dur_rules.json')) as Map<String, dynamic>;
    _bySeq = {for (final d in drugs) d['item_seq'] as String: d};
    _searchKeys = [for (final d in drugs) normalizeForSearch(d['item_name'] as String)];
    _drugs = drugs;
  }

  Map<String, dynamic> _drugJson(String itemSeq) {
    final j = _bySeq[itemSeq];
    if (j == null) throw RepoException('약 정보를 찾을 수 없어요.', code: 'NOT_FOUND');
    return j;
  }

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  final Set<String> _accounts = {'demo@pillflow.app'};

  /// 목업 회원가입: 서버와 같은 규칙 (형식·4자 미만 → 입력값 오류, 같은 이메일 → DUPLICATE)
  @override
  Future<void> signup(String email, String password) async {
    await _delay();
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) || password.length < 4) {
      throw RepoException('입력값을 확인해 주세요.', code: 'VALIDATION_ERROR');
    }
    if (_accounts.contains(e)) throw RepoException('이미 가입된 이메일이에요.', code: 'DUPLICATE');
    _accounts.add(e);
  }

  /// 목업 로그인: 이메일 형식과 비밀번호 4자 이상이면 통과
  @override
  Future<String> login(String email, String password) async {
    await _delay();
    if (!email.contains('@') || password.length < 4) {
      throw RepoException('이메일 또는 비밀번호를 확인해 주세요.', code: 'INVALID_CREDENTIALS');
    }
    return 'mock-token';
  }

  /// 이름 검색. 앞글자가 일치하는 약을 먼저, 그다음 이름이 짧은 순.
  @override
  Future<Paged<DrugSummary>> searchDrugs(String query, {int page = 1, int size = 20}) async {
    await _load();
    await _delay();
    final q = normalizeForSearch(query);
    if (q.isEmpty) return Paged(items: const [], page: page, size: size, total: 0);

    final prefix = <int>[], contains = <int>[];
    for (var i = 0; i < _searchKeys.length; i++) {
      final k = _searchKeys[i];
      if (k.startsWith(q)) {
        prefix.add(i);
      } else if (k.contains(q)) {
        contains.add(i);
      }
    }
    int byLength(int a, int b) => _searchKeys[a].length.compareTo(_searchKeys[b].length);
    prefix.sort(byLength);
    contains.sort(byLength);
    final hits = [...prefix, ...contains];

    final start = (page - 1) * size;
    final items = hits.skip(start).take(size).map((i) => DrugSummary.fromJson(_drugs[i])).toList();
    return Paged(items: items, page: page, size: size, total: hits.length);
  }

  @override
  Future<DrugDetail> getDrug(String itemSeq) async {
    await _load();
    await _delay();
    return DrugDetail.fromJson(_drugJson(itemSeq));
  }

  @override
  Future<List<UserDrug>> getMyDrugs() async {
    await _delay();
    return List.unmodifiable(_myDrugs);
  }

  @override
  Future<UserDrug> addMyDrug(String itemSeq, {String? memo}) async {
    await _load();
    await _delay();
    if (_myDrugs.any((d) => d.itemSeq == itemSeq)) {
      throw RepoException('이미 등록한 약이에요.', code: 'DUPLICATE');
    }
    final j = _drugJson(itemSeq);
    final d = UserDrug(
      id: _nextId++,
      itemSeq: itemSeq,
      itemName: j['item_name'] as String,
      entpName: j['entp_name'] as String?,
      imageUrl: j['image_url'] as String?,
      memo: memo,
      createdAt: _today(),
    );
    _myDrugs.add(d);
    return d;
  }

  @override
  Future<UserDrug> updateMyDrug(int id, {String? memo}) async {
    await _delay();
    final i = _myDrugs.indexWhere((d) => d.id == id);
    if (i < 0) throw RepoException('약을 찾을 수 없어요.', code: 'NOT_FOUND');
    final o = _myDrugs[i];
    final n = UserDrug(
      id: o.id,
      itemSeq: o.itemSeq,
      itemName: o.itemName,
      entpName: o.entpName,
      imageUrl: o.imageUrl,
      memo: memo,
      createdAt: o.createdAt,
    );
    _myDrugs[i] = n;
    return n;
  }

  @override
  Future<void> deleteMyDrug(int id) async {
    await _delay();
    _myDrugs.removeWhere((d) => d.id == id);
    _schedules.removeWhere((s) => s.userDrugId == id); // 연결된 시간표도 삭제
  }

  @override
  Future<List<ScheduleItem>> getSchedules() async {
    await _delay();
    final list = [..._schedules]..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  @override
  Future<ScheduleItem> addSchedule({
    required int userDrugId,
    required String time,
    required MealRelation mealRelation,
    String? doseText,
  }) async {
    await _delay();
    final drug = _myDrugs.firstWhere(
      (d) => d.id == userDrugId,
      orElse: () => throw RepoException('약을 찾을 수 없어요.', code: 'NOT_FOUND'),
    );
    final s = ScheduleItem(
      id: _nextId++,
      userDrugId: userDrugId,
      itemName: drug.itemName,
      time: time,
      mealRelation: mealRelation,
      doseText: doseText,
    );
    _schedules.add(s);
    return s;
  }

  @override
  Future<ScheduleItem> updateSchedule(
    int id, {
    required String time,
    required MealRelation mealRelation,
    String? doseText,
  }) async {
    await _delay();
    final i = _schedules.indexWhere((s) => s.id == id);
    if (i < 0) throw RepoException('복용 시간을 찾을 수 없어요.', code: 'NOT_FOUND');
    final o = _schedules[i];
    final n = ScheduleItem(
      id: o.id,
      userDrugId: o.userDrugId,
      itemName: o.itemName,
      time: time,
      mealRelation: mealRelation,
      doseText: doseText,
    );
    _schedules[i] = n;
    return n;
  }

  @override
  Future<void> deleteSchedule(int id) async {
    await _delay();
    _schedules.removeWhere((s) => s.id == id);
  }

  @override
  Future<List<IntakeRecord>> getIntakes(String date) async {
    await _delay();
    final list = [..._schedules]..sort((a, b) => a.time.compareTo(b.time));
    return list
        .map((s) => IntakeRecord(
              scheduleId: s.id,
              date: date,
              time: s.time,
              itemName: s.itemName,
              status: _intakes['${s.id}|$date'] ?? IntakeStatus.pending,
              recordedAt: _recordedAt['${s.id}|$date'],
            ))
        .toList();
  }

  @override
  Future<void> setIntake({required int scheduleId, required String date, required IntakeStatus status}) async {
    await _delay();
    _intakes['$scheduleId|$date'] = status;
    _recordedAt['$scheduleId|$date'] = DateTime.now().toIso8601String().substring(0, 19);
  }

  @override
  Future<int?> getBirthYear() async => _birthYear;

  @override
  Future<void> setBirthYear(int? year) async => _birthYear = year;

  /// 서버가 할 판별을 흉내냅니다. 규칙: 보고서 5.5
  /// - 데이터에 없는 약 → UNDETERMINED (안전으로 표시 금지)
  /// - 금기 발견 → CONTRAINDICATED (시간 분리로 해결하지 않음)
  @override
  Future<DurCheckResult> checkDur({List<String>? itemSeqs}) async {
    await _load();
    await _delay();
    final seqs = itemSeqs ?? _myDrugs.map((d) => d.itemSeq).toList();
    final covered = (_rules['dur_covered_item_seqs'] as List).cast<String>().toSet();
    final findings = <DurFinding>[];

    for (final r in (_rules['combination_rules'] as List).cast<Map<String, dynamic>>()) {
      final a = r['a_item_seq'] as String, b = r['b_item_seq'] as String;
      if (seqs.contains(a) && seqs.contains(b)) {
        findings.add(DurFinding(
          type: FindingType.combination,
          itemSeqs: [a, b],
          ingredients: [r['ingredient_a'], r['ingredient_b']].whereType<String>().toList(),
          detail: r['detail'] as String,
          conditionNote: r['condition_note'] as String?,
          noticeNo: r['notice_no'] as String?,
          noticeDate: r['notice_date'] as String?,
        ));
      }
    }

    final age = _birthYear == null ? null : DateTime.now().year - _birthYear!;
    if (age != null) {
      for (final r in (_rules['age_rules'] as List).cast<Map<String, dynamic>>()) {
        final seq = r['item_seq'] as String;
        if (!seqs.contains(seq)) continue;
        final limit = r['age'] as int;
        final cond = r['condition'] as String;
        final hit = switch (cond) {
          '미만' => age < limit,
          '이하' => age <= limit,
          '이상' => age >= limit,
          _ => false,
        };
        if (hit) {
          findings.add(DurFinding(
            type: FindingType.age,
            itemSeqs: [seq],
            ingredients: [r['ingredient'] as String],
            detail: '$limit${r['unit']} $cond 금기 · ${r['detail']}',
            noticeNo: r['notice_no'] as String?,
            noticeDate: r['notice_date'] as String?,
          ));
        }
      }
    }

    final flagged = findings.expand((f) => f.itemSeqs).toSet();
    final drugs = seqs.map((s) {
      final name = _drugJson(s)['item_name'] as String;
      final v = flagged.contains(s)
          ? Verdict.contraindicated
          : covered.contains(s)
              ? Verdict.noKnownIssue
              : Verdict.undetermined;
      return DurDrugVerdict(itemSeq: s, itemName: name, verdict: v);
    }).toList();

    final cautions = (_rules['cautions'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(DurCaution.fromJson)
        .where((c) => c.itemSeqs.any(seqs.contains))
        .toList();

    return DurCheckResult(
      dataVersion: _rules['data_version'] as String?,
      checkedAt: _today(),
      ageUnknown: age == null,
      drugs: drugs,
      findings: findings,
      cautions: cautions,
    );
  }

  /// 서버 4-2 규칙을 단순화한 목업: 용법 문장의 "1일 N회"를 읽어 식사 시각에 배치
  @override
  Future<ScheduleSuggestResult> suggestSchedules({List<int>? userDrugIds}) async {
    await _load();
    final targets = _myDrugs.where((d) => userDrugIds == null || userDrugIds.contains(d.id)).toList();
    const base = {'breakfast': '08:00', 'lunch': '12:30', 'dinner': '18:30', 'bedtime': '22:30'};
    final out = <ScheduleSuggestion>[];
    for (final d in targets) {
      final text = (_bySeq[d.itemSeq]?['use_method'] as String?) ?? '';
      final range = RegExp(r'1일\s*(\d+)\s*[~∼-]\s*(\d+)\s*회').firstMatch(text);
      final single = RegExp(r'1일\s*(\d+)\s*회').firstMatch(text);
      final n = range != null ? int.parse(range.group(1)!) : (single != null ? int.parse(single.group(1)!) : null);
      final meal = text.contains('식후')
          ? MealRelation.after
          : text.contains('식전')
              ? MealRelation.before
              : text.contains('공복')
                  ? MealRelation.empty
                  : MealRelation.none;
      final times = switch (n) {
        1 => [base['breakfast']!],
        2 => [base['breakfast']!, base['dinner']!],
        3 => [base['breakfast']!, base['lunch']!, base['dinner']!],
        4 => [base['breakfast']!, base['lunch']!, base['dinner']!, base['bedtime']!],
        _ => <String>[],
      };
      final basis = text.split(RegExp(r'\n')).firstWhere((l) => l.contains('1일'), orElse: () => '').trim();
      final warnings = <String>[
        if (range != null && times.isNotEmpty) '횟수가 범위로 적혀 있어 작은 값($n회)으로 제안했어요. 확인해 주세요.',
      ];
      out.add(ScheduleSuggestion(
        userDrugId: d.id,
        itemSeq: d.itemSeq,
        itemName: d.itemName,
        confidence: times.isEmpty
            ? SuggestConfidence.none
            : (warnings.isEmpty ? SuggestConfidence.high : SuggestConfidence.confirm),
        timesPerDay: times.isEmpty ? null : n,
        slots: [for (final t in times) SuggestSlot(time: t, mealRelation: meal)],
        basis: basis.isEmpty ? null : basis,
        warnings: warnings,
      ));
    }
    final dur = targets.length < 2 ? null : await checkDur(itemSeqs: targets.map((d) => d.itemSeq).toList());
    return ScheduleSuggestResult(
      suggestions: out,
      durFindings: dur?.findings ?? const [],
      notes: const [
        '제안일 뿐이에요. 복용 방법은 처방과 약 설명서를 먼저 따라 주세요.',
        '몇 정·몇 mL를 먹을지는 제안하지 않아요. 한 번에 먹는 양은 직접 입력해 주세요.',
      ],
    );
  }
}
