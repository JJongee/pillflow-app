import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/state_views.dart';
import '../widgets/verdict_badge.dart';

/// DUR 판별 결과 · 경고 · 판정 불가 화면
/// 안전 원칙(보고서 5.5):
///  - 금기 조합은 시간 분리로 해결하지 않는다 → "의사·약사 상담" 안내만
///  - 데이터에 없는 약은 "판정 불가"로 표시 (안전 표시 금지)
///  - 경고에는 고시번호·고시일자·비고(조건)를 함께 표시
class DurResultScreen extends ConsumerWidget {
  const DurResultScreen({super.key});

  Future<void> _askBirthYear(BuildContext context, WidgetRef ref, int? current) async {
    final c = TextEditingController(text: current?.toString() ?? '');
    final y = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('태어난 해'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(hintText: '예: 1958', helperText: '나이에 따라 금기인 약을 확인할 때만 써요.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('저장')),
        ],
      ),
    );
    c.dispose();
    final now = DateTime.now().year;
    if (y == null || !context.mounted) return;
    if (y < 1900 || y > now) {
      if (context.mounted) showSnack(context, '태어난 해를 다시 확인해 주세요.');
      return;
    }
    await ref.read(repositoryProvider).setBirthYear(y);
    ref.invalidate(birthYearProvider);
    ref.invalidate(durCheckProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(durCheckProvider);
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
                  onTap: () => _askBirthYear(context, ref, birthYear),
                ),
              ),
            if (hasDanger) ...[
              const SizedBox(height: 20),
              Text('주의가 필요한 조합', style: t.titleMedium),
              const SizedBox(height: 8),
              ...r.findings.map((f) => _FindingCard(finding: f, names: names)),
              const _ConsultNotice(),
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
                        Text('공공 DUR 데이터에 없는 약이라 판단할 수 없어요. 안전하다는 뜻이 아니에요.',
                            style: t.bodyMedium?.copyWith(color: AppColors.unknown)),
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
                onPressed: () => _askBirthYear(context, ref, birthYear),
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
    final (fg, bg, icon, title) = hasDanger
        ? (AppColors.danger, AppColors.dangerBg, Icons.warning_amber_rounded, '함께 먹으면 안 되는 조합이 있어요')
        : undetermined > 0
            ? (AppColors.unknown, AppColors.unknownBg, Icons.help_outline, '확인된 금기는 없지만, 판단할 수 없는 약이 있어요')
            : (AppColors.ok, AppColors.okBg, Icons.check_circle_outline, '공공 DUR 기준으로 확인된 금기가 없어요');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
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

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, required this.names});
  final DurFinding finding;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = finding;
    final title = f.type == FindingType.combination
        ? f.itemSeqs.map((s) => names[s] ?? s).join('  +  ')
        : names[f.itemSeqs.first] ?? f.itemSeqs.first;
    return Card(
      color: AppColors.dangerBg,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.type == FindingType.combination ? '병용금기' : '연령금기',
              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(title, style: t.titleMedium?.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Text(f.detail, style: t.bodyLarge),
          if (f.conditionNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Text('조건: ${f.conditionNote}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 8),
          Text('성분: ${f.ingredients.join(', ')}', style: t.bodySmall),
          Text('식약처 고시 ${f.noticeNo ?? '-'} · ${f.noticeDate ?? '-'}', style: t.bodySmall),
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
