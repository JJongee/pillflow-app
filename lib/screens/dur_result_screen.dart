import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/dialogs.dart';
import '../widgets/state_views.dart';
import '../widgets/verdict_badge.dart';

/// DUR 판별 결과 · 경고 · 판정 불가 화면
/// 안전 원칙(보고서 5.5):
///  - 금기 조합은 시간 분리로 해결하지 않는다 → "의사·약사 상담" 안내만
///  - 데이터에 없는 약은 "판정 불가"로 표시 (안전 표시 금지)
///  - 경고에는 고시번호·고시일자·비고(조건)를 함께 표시
class DurResultScreen extends ConsumerWidget {
  const DurResultScreen({super.key, this.preview});

  /// 화면 상태 미리보기용. 값이 있으면 서버/목업 대신 이 결과를 그대로 보여줍니다.
  final DurCheckResult? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = preview != null ? AsyncValue.data(preview!) : ref.watch(durCheckProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('함께 먹어도 될까요')),
      body: AsyncBody<DurCheckResult>(
        value: value,
        onRetry: () => ref.invalidate(durCheckProvider),
        data: (r) {
          final names = {for (final d in r.drugs) d.itemSeq: d.itemName};
          final danger = r.contraindications;
          final cautions = r.allCautions;
          final hasDanger = danger.isNotEmpty;
          final undetermined = r.drugs.where((d) => d.verdict == Verdict.undetermined).length;
          // 판정에 쓰는 프로필 값: DUR 응답에 같이 오면 그걸, 없으면 내 프로필
          final sex = r.sex ?? profile?.sex ?? Sex.unknown;
          final subject = r.subject ?? profile?.subject ?? Subject.unknown;
          final prefix = subject.resultPrefix;
          // 임신 중 + 임부금기 해당됨 → 판정(빨간 배너)은 그대로 두고 경고만 세게 (연우 제안)
          final pregHit = cautions.where((c) => c.kind == DurKind.pregnancy && c.applies == Applies.yes).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            _SummaryCard(hasDanger: hasDanger, undetermined: undetermined, total: r.drugs.length),
            if (r.ageUnknown)
              Card(
                margin: const EdgeInsets.only(top: 12),
                child: ListTile(
                  leading: const Icon(Icons.cake_outlined),
                  title: const Text('나이에 따른 금기는 확인하지 않았어요'),
                  subtitle: const Text('생년월일을 입력하면 함께 확인해요.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => editBirthDate(context, ref, profile),
                ),
              ),
            if (hasDanger) ...[
              const SizedBox(height: 20),
              Text('주의가 필요한 조합', style: t.titleMedium),
              const SizedBox(height: 8),
              ...danger.map((f) => _FindingCard(finding: f, names: names)),
              const _ConsultNotice(),
            ],
            if (pregHit.isNotEmpty)
              _PregnancyAlert(
                drugs: {for (final c in pregHit) ...c.itemSeqs.map((x) => names[x] ?? x)}.toList(),
                prefix: prefix,
              ),
            if (cautions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('참고 정보', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                '판정에는 들어가지 않는 내용이에요. \'기준 확인됨\'은 이 약이 DUR 기준에 해당하는 약이라는 뜻일 뿐, '
                '내가 주의 대상이라는 뜻도, 먹어도 된다는 뜻도 아니에요.',
                style: t.bodySmall?.copyWith(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 8),
              // 판정에 쓰는 내 정보를 위에 모아 보여 주고 바로 바꿀 수 있게
              if ((sex != Sex.male || profile?.pregnancy == Pregnancy.pregnant) &&
                  cautions.any((c) => c.kind == DurKind.pregnancy))
                _MyInfoChip(
                  icon: Icons.pregnant_woman_outlined,
                  label: '임신 여부',
                  value: (profile?.pregnancy ?? Pregnancy.unknown).label,
                  onTap: () => editPregnancy(context, ref, profile?.pregnancy ?? Pregnancy.unknown),
                ),
              // 약품별로 묶고, 유형은 한 줄씩 접어서 보여 줌 (손채은 10/8 제안)
              ..._groupBySeqs(cautions).entries.map((e) => _CautionGroup(
                    title: e.value.first.itemSeqs.map((x) => names[x] ?? x).join(', '),
                    cautions: e.value,
                    prefix: prefix,
                    sex: sex,
                  )),
            ],
            const SizedBox(height: 20),
            Text('약별 결과', style: t.titleMedium),
            const SizedBox(height: 8),
            ...r.drugs.map((d) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.itemName, style: t.titleMedium?.copyWith(fontSize: 18)),
                      const SizedBox(height: 8),
                      VerdictBadge(verdict: d.verdict),
                      if (d.verdict == Verdict.undetermined) ...[
                        const SizedBox(height: 8),
                        Text('DUR 정보가 부족하거나 기준을 확인하는 중이라 판단할 수 없어요.',
                            style: t.bodyMedium?.copyWith(color: AppColors.unknown)),
                      ],
                      if (d.verdict == Verdict.noKnownIssue) ...[
                        const SizedBox(height: 8),
                        Text('이번 조합에서 확인된 금기 기록이 없다는 뜻이에요. 문제가 없다는 보장은 아니에요.',
                            style: t.bodyMedium),
                      ],
                    ]),
                  ),
                )),
            const SizedBox(height: 20),
            Text(
              '근거: 식품의약품안전처 DUR(${r.dataVersion ?? '-'}) · 확인일 ${r.checkedAt ?? '-'}\n'
              '이 결과는 공공데이터 안내이며 진단이나 처방을 대신하지 않아요.',
              style: t.bodySmall,
            ),
            if (!r.ageUnknown)
              TextButton(
                onPressed: () => editBirthDate(context, ref, profile),
                child: Text('생년월일 변경 (${profile?.display ?? '-'})'),
              ),
          ]);
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.hasDanger, required this.undetermined, required this.total});
  final bool hasDanger;
  final int undetermined;
  final int total;

  @override
  Widget build(BuildContext context) {
    // "안전"처럼 보이지 않도록 금기 기록이 없을 때도 초록 대신 중립 색을 씁니다.
    final (fg, bg, icon, title) = hasDanger
        ? (AppColors.danger, AppColors.dangerBg, Icons.warning_amber_rounded, '함께 먹으면 안 되는 조합이 있어요')
        : undetermined > 0
            ? (AppColors.unknown, AppColors.unknownBg, Icons.help_outline, '확인된 금기 기록은 없지만, 판단할 수 없는 약이 있어요')
            : (AppColors.neutral, AppColors.neutralBg, Icons.info_outline, '이번 조합에서 확인된 금기 기록이 없어요');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(icon, color: fg, size: 36),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('확인한 약 $total개 · 판정 불가 $undetermined개', style: TextStyle(color: fg, fontSize: 15)),
          ]),
        ),
      ]),
    );
  }
}

/// 라벨 + 값 한 줄 (값이 없으면 줄 자체를 숨김)
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 76, child: Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
        Expanded(child: Text(value!, style: t.bodyMedium)),
      ]),
    );
  }
}

/// 공통 DUR 경고 카드 (손채은 안): 유형에 따라 제목만 바뀌고 구성은 같음
///   관련 성분 · 금기 사유/내용 · 추가 안내(있을 때만) · 고시일(있을 때만)
class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, required this.names});
  final DurFinding finding;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = finding;
    final drugs = f.itemSeqs.map((s) => names[s] ?? s).join('  +  ');
    return Card(
      color: AppColors.dangerBg,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 6),
            Text(f.label, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          Text(drugs, style: t.titleMedium?.copyWith(fontSize: 18)),
          _InfoRow('관련 성분', f.ingredients.isEmpty ? null : f.ingredients.join(', ')),
          _InfoRow(f.type == FindingType.combination ? '금기 사유' : '금기 내용', f.detail),
          _InfoRow('추가 안내', f.conditionNote),
          _InfoRow('고시일', f.noticeDate),
        ]),
      ),
    );
  }
}

const multiStandardNotice = '동일 성분의 제형·농도별 참고정보이며, 현재 약품에 적용되는 기준으로 확정된 것은 아닙니다.';

/// 한 약에 같은 유형이 2건 이상이고 전부 '기준 확인 중'인 유형 (예: 사노바겔 용량주의 3건)
List<String> _multiPendingTypes(List<DurCaution> list) {
  final byType = <String, List<DurCaution>>{};
  for (final c in list) {
    byType.putIfAbsent(c.typeCode, () => []).add(c);
  }
  return [
    for (final e in byType.entries)
      if (e.value.length >= 2 &&
          e.value.every((c) => c.status != CautionStatus.confirmed) &&
          // 서버가 condition_note에 같은 안내를 이미 붙였으면 앱은 따로 띄우지 않음 (겹침 방지)
          !e.value.any((c) => (c.conditionNote ?? '').contains('제형·농도별')))
        e.key,
  ];
}

/// 같은 약(또는 같은 약 묶음)에 붙은 참고 정보끼리 모음. 처음 나온 순서 유지
Map<String, List<DurCaution>> _groupBySeqs(List<DurCaution> list) {
  final out = <String, List<DurCaution>>{};
  for (final c in list) {
    out.putIfAbsent(c.itemSeqs.join('+'), () => []).add(c);
  }
  return out;
}

/// 참고 정보: 약품 하나에 카드 하나, 유형별로 접기/펼치기
///   아나프로스정
///     임부금기 · 기준 확인됨  ⌄
///     용량주의 · 기준 확인 중    ⌄
/// 판정과 섞이지 않게 빨강 대신 주황, '기준 확인 중'은 눈에 띄게 표시
class _CautionGroup extends StatelessWidget {
  const _CautionGroup({required this.title, required this.cautions, required this.prefix, required this.sex});
  final String title;
  final List<DurCaution> cautions;
  final String prefix;
  final Sex sex;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final single = cautions.length == 1;
    // 유형별로 모으기 (처음 나온 유형 순서 유지)
    final byType = <String, List<DurCaution>>{};
    for (final c in cautions) {
      byType.putIfAbsent(c.typeCode, () => []).add(c);
    }
    final ordered = [for (final l in byType.values) ...l];
    final firstOf = {for (final e in byType.entries) e.key: e.value.first};
    final counts = {for (final e in byType.entries) e.key: e.value.length};
    final multi = _multiPendingTypes(cautions).toSet();
    return Card(
      color: AppColors.cautionBg,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(title, style: t.titleMedium?.copyWith(fontSize: 18)),
          ),
          // 같은 유형끼리 붙여서 보여 주고, 제형·농도별 기준이 여러 개(모두 확정 전)인 유형은
          // 그 유형 바로 위에 안내를 붙임 (서현 10/11) — 다른 유형까지 해당하는 것처럼 보이지 않게
          for (final c in ordered) ...[
            if (multi.contains(c.typeCode) && identical(c, firstOf[c.typeCode]))
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(170),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '아래 ${durTypeLabel(c.typeCode)} ${counts[c.typeCode]}건: $multiStandardNotice',
                  style: t.bodySmall?.copyWith(fontSize: 13.5, color: AppColors.caution, height: 1.45),
                ),
              ),
            Theme(
              // ExpansionTile 위아래 구분선 없애기
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: single, // 하나뿐이면 바로 펼쳐 둠
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                iconColor: AppColors.caution,
                collapsedIconColor: AppColors.caution,
                title: _CautionTitle(caution: c, prefix: prefix),
                children: [_CautionBody(caution: c, prefix: prefix, sex: sex)],
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _CautionTitle extends StatelessWidget {
  const _CautionTitle({required this.caution, required this.prefix});
  final DurCaution caution;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final c = caution;
    final statusColor = c.status == CautionStatus.confirmed ? AppColors.neutral : AppColors.caution;
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(c.label, style: const TextStyle(color: AppColors.caution, fontWeight: FontWeight.w800, fontSize: 16)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: statusColor.withAlpha(110)),
        ),
        child: Text(c.status.label, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      // 판정 결과는 데이터 연결 상태와 다른 칸 → 모양을 달리해서(채운 배지) 섞이지 않게
      if (c.applies != null) _AppliesPill(applies: c.applies!, prefix: prefix),
    ]);
  }
}

/// 임신 중 + 임부금기 해당됨: 결과 위쪽에 눈에 띄게 (판정 배너와는 별도)
class _PregnancyAlert extends StatelessWidget {
  const _PregnancyAlert({required this.drugs, required this.prefix});
  final List<String> drugs;
  final String prefix;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.danger, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.pregnant_woman, color: AppColors.danger, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text('임신 중에 금기인 약이 있어요',
                  style: TextStyle(color: AppColors.danger, fontSize: 19, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          ...drugs.map((d) => Text('· $d', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          Text(
            '${prefix == '복용하는 분' ? '복용하는 분이 ' : ''}임신 중으로 입력되어 있어요. '
            '임의로 먹거나 끊지 말고, 처방한 의사나 약사와 먼저 상담해 주세요.',
            style: const TextStyle(color: AppColors.danger, fontSize: 15, height: 1.45),
          ),
        ]),
      );
}

/// 판정에 쓰는 내 정보 한 줄: "임신 여부 · 응답 안 함   바꾸기 >"
class _MyInfoChip extends StatelessWidget {
  const _MyInfoChip({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Toss.blue50,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(icon, color: Toss.blue),
                const SizedBox(width: 10),
                Text('$label · ', style: const TextStyle(fontSize: 16, color: Toss.grey700)),
                Expanded(
                  child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Toss.grey900)),
                ),
                const Text('바꾸기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Toss.blue)),
                const Icon(Icons.chevron_right, color: Toss.blue),
              ]),
            ),
          ),
        ),
      );
}

/// 판정 결과 배지: 해당됨(빨강) · 확인 필요(주황) · 해당 안 됨(회색, 초록 쓰지 않음)
class _AppliesPill extends StatelessWidget {
  const _AppliesPill({required this.applies, required this.prefix});
  final Applies applies;
  final String prefix;

  static (Color, Color) colors(Applies a) => switch (a) {
        Applies.yes => (Colors.white, AppColors.danger),
        Applies.check || Applies.unknown => (Colors.white, AppColors.caution),
        Applies.no => (AppColors.neutral, AppColors.neutralBg),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colors(applies);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text('$prefix · ${applies.label}', style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}

class _CautionBody extends ConsumerWidget {
  const _CautionBody({required this.caution, required this.prefix, required this.sex});
  final DurCaution caution;
  final String prefix;
  final Sex sex;

  /// 판정 결과 상자: applies_note 그대로 + 입력이 없어서(UNKNOWN) 모를 때만 입력을 권함
  Widget _appliesBox(BuildContext context, WidgetRef ref, DurCaution c) {
    final t = Theme.of(context).textTheme;
    final a = c.applies!;
    final (_, accent) = _AppliesPill.colors(a);
    final color = a == Applies.no ? AppColors.neutral : accent;
    Widget? action;
    final curPreg = ref.watch(profileProvider).valueOrNull?.pregnancy;
    if (c.kind == DurKind.pregnancy && (sex != Sex.male || curPreg == Pregnancy.pregnant)) {
      // 입력 전이면 '입력', 입력했으면 지금 값과 함께 '바꾸기'
      final cur = ref.watch(profileProvider).valueOrNull?.pregnancy ?? Pregnancy.unknown;
      action = TextButton.icon(
        onPressed: () => editPregnancy(context, ref, cur),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: Text(cur == Pregnancy.unknown ? '임신 여부 입력' : '임신 여부 바꾸기 (지금: ${cur.label})'),
      );
    } else if (a == Applies.unknown && c.kind == DurKind.duration) {
      action = Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('"내 약" → 약 오른쪽 ⋮ → 복용 기간에서 시작일을 입력해 주세요.', style: t.bodySmall?.copyWith(fontSize: 13.5)),
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$prefix · ${a.label}', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        if (c.appliesNote != null) ...[
          const SizedBox(height: 4),
          Text(c.appliesNote!, style: t.bodyMedium?.copyWith(fontSize: 15)),
        ],
        if (action != null) action,
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = caution;
    final rows = <Widget>[];
    if (c.info.isNotEmpty) {
      // 서버가 정리해 준 줄을 그대로 (값이 있는 칸만 옴 → 빈 줄 없음)
      rows.addAll(c.info.map((l) => _InfoRow(l.label, l.value)));
      if (!c.info.any((l) => l.label == '추가 안내')) rows.add(_InfoRow('추가 안내', c.conditionNote));
      if (!c.info.any((l) => l.label == '고시일')) rows.add(_InfoRow('고시일', c.noticeDate));
    } else {
      // info가 없는 예전 응답: 유형별로 보여 줄 줄만 다르고 형식은 같음
      if (c.kind == DurKind.efficacyDuplicate) {
        rows.add(_InfoRow('효능군', c.efficacyGroup));
        rows.add(_InfoRow('계열', c.series));
      }
      if (c.kind == DurKind.duration) rows.add(_InfoRow('기간 기준', c.periodText));
      rows.addAll([
        _InfoRow('관련 성분', c.ingredients.isEmpty ? null : c.ingredients.join(', ')),
        _InfoRow(c.kind == DurKind.elderly ? '주의 내용' : '내용', c.detail),
        _InfoRow('추가 안내', c.conditionNote),
        _InfoRow('고시일', c.noticeDate),
      ]);
    }
    final empty = c.info.isEmpty &&
        c.detail.trim().isEmpty &&
        c.conditionNote == null &&
        c.periodText == null &&
        c.efficacyGroup == null &&
        c.ingredients.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.hint, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      if (c.applies != null) _appliesBox(context, ref, c),
      ...rows,
      // 정보가 비어 있어도 '괜찮음'으로 보이지 않게
      if (empty) ...[
        const SizedBox(height: 8),
        Text('세부 내용이 아직 없어요. 해당되지 않는다는 뜻은 아니니 약사와 확인해 주세요.', style: t.bodyMedium),
      ],
      if (c.status != CautionStatus.confirmed) ...[
        const SizedBox(height: 8),
        Text('기준을 확인하는 중인 정보예요. 해당되지 않는다는 뜻이 아니니 약사와 상담해 주세요.',
            style: t.bodySmall?.copyWith(color: AppColors.caution)),
      ],
    ]);
  }
}

/// 금기 조합은 시간 분리로 해결하지 않고 전문가 상담을 안내합니다.
class _ConsultNotice extends StatelessWidget {
  const _ConsultNotice();

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.local_pharmacy_outlined, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '먹는 시간을 나눠도 해결되지 않는 조합이에요. 임의로 복용을 멈추거나 바꾸지 말고, '
                '처방한 의사나 약사와 먼저 상담해 주세요.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ]),
        ),
      );
}
