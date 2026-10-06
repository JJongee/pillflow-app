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
    final birthYear = ref.watch(birthYearProvider).valueOrNull;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('함께 먹어도 될까요')),
      body: AsyncBody<DurCheckResult>(
        value: value,
        onRetry: () => ref.invalidate(durCheckProvider),
        data: (r) {
          final names = {for (final d in r.drugs) d.itemSeq: d.itemName};
          final hasDanger = r.findings.isNotEmpty;
          final undetermined = r.drugs.where((d) => d.verdict == Verdict.undetermined).length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            _SummaryCard(hasDanger: hasDanger, undetermined: undetermined, total: r.drugs.length),
            if (r.ageUnknown)
              Card(
                margin: const EdgeInsets.only(top: 12),
                child: ListTile(
                  leading: const Icon(Icons.cake_outlined),
                  title: const Text('나이에 따른 금기는 확인하지 않았어요'),
                  subtitle: const Text('태어난 해를 입력하면 함께 확인해요.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => editBirthYear(context, ref, birthYear),
                ),
              ),
            if (hasDanger) ...[
              const SizedBox(height: 20),
              Text('주의가 필요한 조합', style: t.titleMedium),
              const SizedBox(height: 8),
              ...r.findings.map((f) => _FindingCard(finding: f, names: names)),
              const _ConsultNotice(),
            ],
            if (r.cautions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('참고 정보', style: t.titleMedium),
              const SizedBox(height: 4),
              Text('판정에는 들어가지 않지만 확인이 필요한 내용이에요.', style: t.bodySmall),
              const SizedBox(height: 8),
              ...r.cautions.map((c) => _CautionCard(caution: c, names: names)),
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
                onPressed: () => editBirthYear(context, ref, birthYear),
                child: Text('태어난 해 변경 (${birthYear ?? '-'})'),
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

/// 참고 정보 카드 (임부금기·용량주의). 판정과 섞이지 않게 빨간색 대신 주황 계열,
/// '기준 확인 중'이면 상태를 눈에 띄게 표시해 "괜찮음"으로 오해하지 않게 합니다.
class _CautionCard extends StatelessWidget {
  const _CautionCard({required this.caution, required this.names});
  final DurCaution caution;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = caution;
    final drugs = c.itemSeqs.map((s) => names[s] ?? s).join(', ');
    final statusColor = c.status == CautionStatus.confirmed ? AppColors.neutral : AppColors.caution;
    return Card(
      color: AppColors.cautionBg,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, color: AppColors.caution, size: 20),
              const SizedBox(width: 6),
              Text(c.label, style: const TextStyle(color: AppColors.caution, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withAlpha(110)),
              ),
              child: Text(c.status.label,
                  style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(drugs, style: t.titleMedium?.copyWith(fontSize: 18)),
          const SizedBox(height: 2),
          Text(c.hint, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          _InfoRow('관련 성분', c.ingredients.isEmpty ? null : c.ingredients.join(', ')),
          _InfoRow('내용', c.detail),
          _InfoRow('추가 안내', c.conditionNote),
          _InfoRow('고시일', c.noticeDate),
          if (c.status != CautionStatus.confirmed) ...[
            const SizedBox(height: 8),
            Text('기준을 확인하는 중인 정보예요. 해당되지 않는다는 뜻이 아니니 약사와 상담해 주세요.',
                style: t.bodySmall?.copyWith(color: AppColors.caution)),
          ],
        ]),
      ),
    );
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
