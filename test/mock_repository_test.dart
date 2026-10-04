import 'package:flutter_test/flutter_test.dart';
import 'package:pillflow/data/mock_repository.dart';
import 'package:pillflow/data/repository.dart';
import 'package:pillflow/models/models.dart';

// 목업 데이터(assets/mock)의 실제 품목코드
const aspirin = '200008591'; // 바이엘아스피린정500밀리그람
const ketorolac = 'EDI-649802851'; // 케토신주사 (DUR 전용 품목)
const geborin = '197900277'; // 게보린정 (15세 미만 연령금기)
const hwalmyungsu = '195700020'; // 활명수 (DUR 데이터에 없음)

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle 로 assets 읽기

  test('로그인: 잘못된 형식은 거부, 올바르면 토큰', () async {
    final r = MockRepository();
    await expectLater(r.login('abc', '1'), throwsA(isA<RepoException>()));
    expect(await r.login('demo@pillflow.app', '1234'), isNotEmpty);
  });

  test('병용금기 조합은 CONTRAINDICATED, 데이터에 없는 약은 UNDETERMINED', () async {
    final r = MockRepository();
    await r.addMyDrug(aspirin);
    await r.addMyDrug(ketorolac);
    await r.addMyDrug(hwalmyungsu);

    final res = await r.checkDur();
    final v = {for (final d in res.drugs) d.itemSeq: d.verdict};
    expect(v[aspirin], Verdict.contraindicated);
    expect(v[ketorolac], Verdict.contraindicated);
    expect(v[hwalmyungsu], Verdict.undetermined); // 절대 "안전"이 아님
    expect(res.findings.single.type, FindingType.combination);
    expect(res.findings.single.noticeNo, '20080068');
    expect(res.ageUnknown, isTrue);
  });

  test('연령금기: 나이를 입력해야만 판별', () async {
    final r = MockRepository();
    await r.addMyDrug(geborin);
    expect((await r.checkDur()).findings, isEmpty); // 나이 모름 → 판별 안 함

    await r.setBirthYear(DateTime.now().year - 10); // 10세
    final res = await r.checkDur();
    expect(res.findings.single.type, FindingType.age);
    expect(res.drugs.single.verdict, Verdict.contraindicated);

    await r.setBirthYear(DateTime.now().year - 40); // 40세
    final adult = await r.checkDur();
    expect(adult.findings, isEmpty);
    expect(adult.drugs.single.verdict, Verdict.noKnownIssue); // DUR 데이터에 있는 약
  });

  test('같은 약 중복 등록은 DUPLICATE', () async {
    final r = MockRepository();
    await r.addMyDrug(aspirin);
    await expectLater(
      r.addMyDrug(aspirin),
      throwsA(isA<RepoException>().having((e) => e.code, 'code', 'DUPLICATE')),
    );
  });

  test('시간표 수정 · 약 삭제 시 시간표와 오늘 기록도 정리', () async {
    final r = MockRepository();
    final d = await r.addMyDrug(aspirin);
    final s = await r.addSchedule(userDrugId: d.id, time: '08:30', mealRelation: MealRelation.after);

    final u = await r.updateSchedule(s.id, time: '21:00', mealRelation: MealRelation.empty, doseText: '1정');
    expect(u.time, '21:00');
    expect((await r.getSchedules()).single.mealRelation, MealRelation.empty);

    await r.setIntake(scheduleId: s.id, date: '2026-10-05', status: IntakeStatus.taken);
    expect((await r.getIntakes('2026-10-05')).single.status, IntakeStatus.taken);

    await r.deleteMyDrug(d.id);
    expect(await r.getSchedules(), isEmpty);
    expect(await r.getIntakes('2026-10-05'), isEmpty);
  });

  test('전체 데이터 검색: 앞글자 일치 우선, 띄어쓰기 무시', () async {
    final r = MockRepository();
    final a = await r.searchDrugs('타이레놀');
    expect(a.total, 7); // 앞글자 일치 4 + 포함 3
    expect(a.items.first.itemName.startsWith('타이레놀'), isTrue);

    final b = await r.searchDrugs('타이 레놀');
    expect(b.total, a.total);
  });

  test('전체 데이터 검색: 페이지 나눠 받기', () async {
    final r = MockRepository();
    final p1 = await r.searchDrugs('정', page: 1, size: 20);
    final p2 = await r.searchDrugs('정', page: 2, size: 20);
    expect(p1.total, greaterThan(1000));
    expect(p1.items.length, 20);
    expect(p2.items.length, 20);
    expect(p1.items.map((e) => e.itemSeq).toSet().intersection(p2.items.map((e) => e.itemSeq).toSet()), isEmpty);

    final beyond = await r.searchDrugs('정', page: 999, size: 20);
    expect(beyond.items, isEmpty);
  });

  test('김서현 DB에서 확인된 조합: 멕시롱액 + 코메키나캡슐 (역순 등록도 동일)', () async {
    final r = MockRepository();
    await r.addMyDrug('201706199'); // 코메키나캡슐 먼저
    await r.addMyDrug('199300273'); // 멕시롱액(돔페리돈)
    final res = await r.checkDur();
    expect(res.findings.single.type, FindingType.combination);
    expect(res.findings.single.ingredients, isEmpty); // 목업엔 성분 정보 없음 → 화면에서 줄 숨김
    expect(res.drugs.every((d) => d.verdict == Verdict.contraindicated), isTrue);
  });
}
