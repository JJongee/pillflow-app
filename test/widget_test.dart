import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillflow/models/models.dart';
import 'package:pillflow/widgets/dose_field.dart';
import 'package:pillflow/widgets/verdict_badge.dart';

void main() {
  test('서버 응답의 판정 코드를 해석한다 (모르는 값은 판정 불가)', () {
    expect(Verdict.fromCode('CONTRAINDICATED'), Verdict.contraindicated);
    expect(Verdict.fromCode('NO_KNOWN_ISSUE'), Verdict.noKnownIssue);
    expect(Verdict.fromCode('SOMETHING_NEW'), Verdict.undetermined);
    expect(Verdict.fromCode(null), Verdict.undetermined);
  });

  test('DUR 응답 JSON을 파싱한다', () {
    final r = DurCheckResult.fromJson({
      'data_version': 'DUR 게시 2609',
      'checked_at': '2026-10-05',
      'age_unknown': true,
      'drugs': [
        {'item_seq': 200008591, 'item_name': '바이엘아스피린정500밀리그람', 'verdict': 'CONTRAINDICATED'},
      ],
      'findings': [
        {
          'type': 'COMBINATION',
          'item_seqs': ['200008591', 'EDI-649802851'],
          'ingredients': ['aspirin', 'ketorolac tromethamine'],
          'detail': '중증의 위장관계 이상반응',
          'condition_note': '',
          'notice_no': '20080068',
          'notice_date': '2008-01-01',
        }
      ],
    });
    expect(r.drugs.single.itemSeq, '200008591'); // 숫자로 와도 문자열로
    expect(r.findings.single.conditionNote, isNull); // 빈 문자열은 null
    expect(r.ageUnknown, isTrue);
  });

  testWidgets('판정 불가 배지는 글자로 표시된다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VerdictBadge(verdict: Verdict.undetermined)),
    ));
    expect(find.text('판정 불가'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  test('서버 v0.3 응답: 모르는 유형·cautions·기준 확인 중을 안전하게 해석', () {
    final r = DurCheckResult.fromJson({
      'data_version': 'DUR API 수집 2026-10-04',
      'age_unknown': false,
      'drugs': [
        {'item_seq': '1', 'item_name': 'A', 'verdict': 'NO_KNOWN_ISSUE'},
      ],
      'findings': [
        {'type': 'ELDERLY', 'item_seqs': ['1'], 'ingredients': [], 'detail': '노인 주의', 'notice_no': null},
      ],
      'cautions': [
        {'type': 'PREGNANCY', 'item_seqs': ['1'], 'ingredients': ['x'], 'status': 'PENDING', 'grade': '2등급', 'detail': 'd'},
        {'type': 'DOSE', 'item_seqs': ['1'], 'status': 'SOMETHING_NEW', 'detail': 'd2'},
      ],
      'notes': ['무시해도 됨'],
    });
    expect(r.findings.single.type, FindingType.other);
    expect(r.findings.single.label, '노인주의');
    expect(r.cautions.first.status, CautionStatus.pending);
    expect(r.cautions.first.label, '임부금기');
    expect(r.cautions.last.status, CautionStatus.pending); // 모르는 상태 → 확인 중
    expect(Verdict.noKnownIssue.label, '확인된 금기 기록 없음');
    // 노인주의가 findings로 와도 금기로 세지 않고 참고 정보(기준 확인 중)로 옮김
    expect(r.contraindications, isEmpty);
    expect(r.allCautions.length, 3);
    expect(r.allCautions.last.label, '노인주의');
    expect(r.allCautions.last.status, CautionStatus.pending);
  });

  test('2단계 참고 정보: 효능군·계열·기간 원문을 그대로 읽는다', () {
    final dup = DurCaution.fromJson({
      'type': 'EFFICACY_DUPLICATE', 'item_seqs': ['1', '2'], 'status': 'CONFIRMED',
      'detail': '같은 효능군', 'efficacy_group': '해열진통제', 'series': '아세트아미노펜계',
    });
    expect(dup.label, '효능군중복주의');
    expect(dup.efficacyGroup, '해열진통제');
    expect(dup.series, '아세트아미노펜계');
    expect(dup.status.label, '기준 확인됨');
    expect(dup.hint, isNot(contains('중복 복용이에요')));
    final dur = DurCaution.fromJson({'type': 'DURATION', 'item_seqs': ['1'], 'period_text': '성인 5일, 소아 3일'});
    expect(dur.label, '투여기간주의');
    expect(dur.periodText, '성인 5일, 소아 3일'); // 숫자 하나로 줄이지 않음
    expect(dur.status, CautionStatus.pending);
  });

  test('시간표 제안 응답을 파싱한다', () {
    final r = ScheduleSuggestResult.fromJson({
      'suggestions': [
        {
          'user_drug_id': 12, 'item_seq': '202106092', 'item_name': '타이레놀', 'confidence': 'CONFIRM',
          'times_per_day': 3,
          'slots': [{'time': '08:00', 'meal_relation': 'NONE'}],
          'basis': '1일 3~4회', 'warnings': ['확인해 주세요'],
        }
      ],
      'base_times': {'wake': '07:00'},
      'dur_findings': [],
      'notes': ['제안일 뿐이에요.'],
    });
    expect(r.suggestions.single.confidence, SuggestConfidence.confirm);
    expect(r.suggestions.single.slots.single.time, '08:00');
    expect(r.notes, isNotEmpty);
  });

  test('info: 받은 칸만 줄로 (여러 형식 허용, 빈 값은 버림)', () {
    final a = DurCaution.fromJson({
      'type': 'ELDERLY', 'item_seqs': ['1'], 'status': 'CONFIRMED',
      'info': {'성분': '나프록센나트륨', '제형': '정제', '주의 내용': ''},
    });
    expect(a.info.map((l) => l.label), ['성분', '제형']);
    final b = InfoLine.parse([
      {'label': '기간 기준', 'value': '5일'},
      ['효능군', '해열진통제'],
      '계열: 프로피온산계',
      {'label': '빈칸', 'value': null},
    ]);
    expect(b.map((l) => '${l.label}=${l.value}'), ['기간 기준=5일', '효능군=해열진통제', '계열=프로피온산계']);
    expect(InfoLine.parse(null), isEmpty);
  });

  test('프로필: 생년월일 우선, 없으면 태어난 해 / 시간표 제안 age_known', () {
    final p = Profile.fromJson({'birth_year': 1958, 'birth_date': '1958-03-15'});
    expect(p.display, '1958.03.15');
    expect(Profile.fromJson({'birth_year': 1958, 'birth_date': null}).display, '1958년생');
    expect(const Profile().hasAge, isFalse);
    expect(dateString(DateTime(1958, 3, 5)), '1958-03-05');
    expect(ScheduleSuggestResult.fromJson({'suggestions': [], 'age_known': false}).ageKnown, isFalse);
    expect(ScheduleSuggestResult.fromJson({'suggestions': []}).ageKnown, isNull);
  });

  test('1회 복용량: 숫자+단위로 읽기', () {
    expect(DoseField.parse('1정'), ('1', '정'));
    expect(DoseField.parse('2.5 mL'), ('2.5', 'mL'));
    expect(DoseField.parse('반 알'), isNull);
  });

  testWidgets('1회 복용량: 숫자를 바꾸면 "2캡슐"처럼 저장값이 만들어진다', (tester) async {
    final c = TextEditingController(text: '1캡슐');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DoseField(controller: c))));
    await tester.enterText(find.byType(TextField), '2');
    expect(c.text, '2캡슐');
  });
}
