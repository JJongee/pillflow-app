import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';
import '../widgets/verdict_badge.dart';
import 'dur_result_screen.dart';
import 'login_screen.dart';

/// UI 검수용: 평소엔 일부러 만들어야 보이는 화면 상태를 버튼 하나로 확인합니다.
/// (손채은 님 체크리스트 항목과 1:1)
class StatePreviewScreen extends StatelessWidget {
  const StatePreviewScreen({super.key});

  static const _longName = '케논에스플라스타(케토프로펜) 수출명: 케논에스플라스타(Kenon-S Plaster), '
      '케토플라스트패취(Ketoplast Patch), 케토밴드(Ketoband), 케토티디디에스 플라스타( Keto-TDDS Plaster), '
      '케토덤플라스타(Ketoderm Plaster)';

  void _open(BuildContext context, String title, Widget body) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)),
      );

  void _openScreen(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(s,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('화면 상태 미리보기')),
      body: ListView(children: [
        header('공통 상태'),
        item(Icons.hourglass_empty, '로딩 중', '데이터를 불러오는 동안', () => _open(context, '약 찾기', const LoadingView(message: '찾는 중이에요'))),
        item(Icons.search_off, '검색 결과 0건', '"ㅋㅋㅋ" 검색 결과가 없을 때', () {
          _open(
            context,
            '약 찾기',
            const EmptyView(
              icon: Icons.search_off,
              title: '"ㅋㅋㅋ" 검색 결과가 없어요',
              message: '띄어쓰기 없이, 또는 이름 앞부분만 입력해 보세요.',
            ),
          );
        }),
        item(Icons.cloud_off, '서버 연결 실패 (API 오류)', '서버가 꺼져 있거나 인터넷이 끊겼을 때', () {
          _open(
            context,
            '약 찾기',
            ErrorView(
              error: RepoException('서버에 연결할 수 없어요. 서버가 켜져 있는지 확인해 주세요.', code: 'NETWORK'),
              onRetry: () => showSnack(context, '다시 시도 (미리보기)'),
            ),
          );
        }),
        item(Icons.lock_outline, '로그인 실패 메시지', '이메일 또는 비밀번호가 틀렸을 때',
            () => _openScreen(context, const LoginScreen(initialError: '이메일 또는 비밀번호를 확인해 주세요.'))),
        header('빈 화면'),
        item(Icons.event_available_outlined, '오늘 먹을 약 없음', '복용 시간표가 비어 있는 날', () {
          _open(
            context,
            '오늘',
            const EmptyView(
              icon: Icons.event_available_outlined,
              title: '오늘 먹을 약이 없어요',
              message: '"시간표" 탭에서 복용 시간을 추가해 주세요.',
            ),
          );
        }),
        item(Icons.medication_outlined, '등록한 약 없음', '내 약 목록이 비어 있을 때', () {
          _open(
            context,
            '내 약',
            const EmptyView(
              icon: Icons.medication_outlined,
              title: '등록한 약이 없어요',
              message: '"약 찾기" 탭에서 먹고 있는 약을 검색해 등록해 주세요.',
            ),
          );
        }),
        header('DUR 판정'),
        item(Icons.warning_amber_rounded, '금기 있음 + 참고 정보', '병용·연령금기 카드 + 임부금기(기준 확인 중)·용량주의',
            () => _openScreen(context, DurResultScreen(preview: _danger))),
        item(Icons.layers_outlined, '참고 정보 5종 (예시)', '약품별 묶음 · 유형별 접기/펼치기',
            () => _openScreen(context, DurResultScreen(preview: _stage2))),
        item(Icons.info_outline, '확인된 금기 기록 없음', '안전으로 보이지 않게 중립 색으로 표시',
            () => _openScreen(context, DurResultScreen(preview: _clean))),
        item(Icons.help_outline, '판정 불가 포함', 'DUR 데이터에 없는 약이 섞여 있을 때',
            () => _openScreen(context, DurResultScreen(preview: _undetermined))),
        item(Icons.label_outline, '판정 배지 3종', '색 + 아이콘 + 글자', () {
          _open(
            context,
            '판정 배지',
            const Padding(
              padding: EdgeInsets.all(24),
              child: Wrap(spacing: 12, runSpacing: 12, children: [
                VerdictBadge(verdict: Verdict.contraindicated, large: true),
                VerdictBadge(verdict: Verdict.noKnownIssue, large: true),
                VerdictBadge(verdict: Verdict.undetermined, large: true),
              ]),
            ),
          );
        }),
        header('긴 약품명'),
        item(Icons.short_text, '긴 약품명 (150자)', '목록·상세 제목에서 줄바꿈 확인', () {
          _open(
            context,
            '긴 약품명',
            ListView(padding: const EdgeInsets.all(16), children: [
              Text('검색 목록', style: Theme.of(context).textTheme.titleSmall),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: DrugImage(),
                title: Text(_longName),
                subtitle: Text('한국존슨앤드존슨판매(유)'),
                trailing: Icon(Icons.chevron_right),
              ),
              const Divider(height: 32),
              Text('상세 화면 제목', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const DrugImage(size: 96),
                const SizedBox(width: 16),
                Expanded(child: Text(_longName, style: Theme.of(context).textTheme.titleLarge)),
              ]),
              const Divider(height: 32),
              Text('시간표 한 줄', style: Theme.of(context).textTheme.titleSmall),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text('08:30', style: Theme.of(context).textTheme.titleLarge),
                title: const Text(_longName),
                subtitle: const Text('식후 · 1매'),
              ),
            ]),
          );
        }),
        const SizedBox(height: 24),
      ]),
    );
  }
}

// ---- DUR 미리보기 데이터 (문구는 실제 병용금기·연령금기 파일에서 가져옴) ----

const _danger = DurCheckResult(
  dataVersion: 'DUR 게시 2609 (미리보기)',
  checkedAt: '2026-10-05',
  ageUnknown: false,
  drugs: [
    DurDrugVerdict(itemSeq: 'A', itemName: '바이엘아스피린정500밀리그람', verdict: Verdict.contraindicated),
    DurDrugVerdict(itemSeq: 'B', itemName: '케토신주사(케토롤락트로메타민염)', verdict: Verdict.contraindicated),
    DurDrugVerdict(itemSeq: 'C', itemName: '게보린정(수출명:돌로린정)', verdict: Verdict.contraindicated),
    DurDrugVerdict(itemSeq: 'D', itemName: '타이레놀정500밀리그람(아세트아미노펜)', verdict: Verdict.noKnownIssue),
  ],
  findings: [
    DurFinding(
      type: FindingType.combination,
      itemSeqs: ['A', 'B'],
      ingredients: ['aspirin', 'ketorolac tromethamine'],
      detail: '중증의 위장관계 이상반응',
      conditionNote: '48시간 이내 병용금기',
      noticeNo: '20080068',
      noticeDate: '2008-01-01',
    ),
    DurFinding(
      type: FindingType.age,
      itemSeqs: ['C'],
      ingredients: ['isopropylantipyrine 함유제제'],
      detail: '15세 미만 금기 · 이소프로필안티피린 함유제제(단일제, 복합제)',
      noticeNo: '20110227',
      noticeDate: '2011-11-24',
    ),
  ],
  cautions: [
    DurCaution(
      typeCode: 'PREGNANCY',
      itemSeqs: ['C'],
      ingredients: ['이소프로필안티피린'],
      status: CautionStatus.pending,
      grade: '2등급',
      detail: '임부금기 2등급 · 임부에 대한 안전성 미확립 (미리보기 예시)',
    ),
    DurCaution(
      typeCode: 'DOSE',
      itemSeqs: ['D'],
      ingredients: ['아세트아미노펜'],
      status: CautionStatus.confirmed,
      detail: '1일 최대 투여량 아세트아미노펜 4,000밀리그램',
      conditionNote: '모든 제형 / 단일제·복합제 포함 / 하루 복용량이 이 양을 넘지 않게 하세요.',
      noticeDate: '2014-12-30',
    ),
  ],
);

const _clean = DurCheckResult(
  dataVersion: 'DUR 게시 2609 (미리보기)',
  checkedAt: '2026-10-05',
  ageUnknown: false,
  drugs: [
    DurDrugVerdict(itemSeq: 'A', itemName: '타이레놀정500밀리그람(아세트아미노펜)', verdict: Verdict.noKnownIssue),
    DurDrugVerdict(itemSeq: 'B', itemName: '베아제정', verdict: Verdict.noKnownIssue),
  ],
  findings: [],
);

const _undetermined = DurCheckResult(
  dataVersion: 'DUR 게시 2609 (미리보기)',
  checkedAt: '2026-10-05',
  ageUnknown: true,
  drugs: [
    DurDrugVerdict(itemSeq: 'A', itemName: '타이레놀정500밀리그람(아세트아미노펜)', verdict: Verdict.noKnownIssue),
    DurDrugVerdict(itemSeq: 'B', itemName: '활명수', verdict: Verdict.undetermined),
  ],
  findings: [],
);

// 참고 정보 5종 · 약품별 묶음 확인용. 문구는 예시 (서버 info 형식: 받은 칸만 줄로 표시)
const _stage2 = DurCheckResult(
  dataVersion: '참고 정보 예시 (미리보기)',
  checkedAt: '2026-10-08',
  ageUnknown: false,
  drugs: [
    DurDrugVerdict(itemSeq: 'A', itemName: '예시약 A (나프록센나트륨)', verdict: Verdict.noKnownIssue),
    DurDrugVerdict(itemSeq: 'B', itemName: '예시약 B', verdict: Verdict.noKnownIssue),
  ],
  findings: [],
  cautions: [
    DurCaution(
      typeCode: 'PREGNANCY', itemSeqs: ['A'], ingredients: [], status: CautionStatus.confirmed, detail: '',
      info: [InfoLine('등급', '2등급'), InfoLine('성분', '나프록센나트륨'), InfoLine('금기 사유', '예시 사유')],
    ),
    DurCaution(
      typeCode: 'ELDERLY', itemSeqs: ['A'], ingredients: [], status: CautionStatus.confirmed, detail: '',
      info: [InfoLine('성분', '나프록센나트륨'), InfoLine('제형', '정제')], // 노인주의는 주의 내용 없이 옴
    ),
    DurCaution(
      typeCode: 'DOSE', itemSeqs: ['A'], ingredients: [], status: CautionStatus.pending, detail: '',
      info: [InfoLine('성분', '나프록센나트륨'), InfoLine('1일 최대량', '예시 값'), InfoLine('제형', '정제')],
    ),
    DurCaution(
      typeCode: 'DURATION', itemSeqs: ['A'], ingredients: [], status: CautionStatus.confirmed, detail: '',
      info: [InfoLine('기간 기준', '원문 그대로 표시 (예시)'), InfoLine('성분', '나프록센나트륨')],
    ),
    DurCaution(
      typeCode: 'DUPLICATE', itemSeqs: ['B'], ingredients: [], status: CautionStatus.confirmed, detail: '',
      info: [InfoLine('효능군', '해열진통소염제 (예시)'), InfoLine('계열', '예시 계열'), InfoLine('성분', '예시 성분')],
    ),
  ],
);
