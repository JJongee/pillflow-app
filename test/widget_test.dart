import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillflow/models/models.dart';
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
}
