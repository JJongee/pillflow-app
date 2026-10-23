import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/adherence.dart';
import '../data/custom_photos.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/custom_drug_widgets.dart';
import '../widgets/dialogs.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';
import 'custom_drug_screen.dart';
import 'drug_detail_screen.dart';
import 'dur_result_screen.dart';
import 'schedule_screen.dart';

class MyDrugsScreen extends ConsumerWidget {
  const MyDrugsScreen({super.key});

  /// 직접 추가 → 저장되면 바로 복용 시간 정하기
  static Future<void> addCustom(BuildContext context, WidgetRef ref, {String? name}) async {
    final d = await Navigator.of(context)
        .push<UserDrug>(MaterialPageRoute(builder: (_) => CustomDrugScreen(initialName: name)));
    if (d == null || !context.mounted) return;
    final saved = await openScheduleSheet(context, ref, drugs: [d]);
    if (context.mounted) {
      showSnack(context, saved ? '추가하고 복용 시간도 정했어요.' : '추가했어요. 시간표 탭에서 시간을 정할 수 있어요.');
    }
  }

  Future<void> _editCustom(BuildContext context, WidgetRef ref, UserDrug d) => Navigator.of(context)
      .push<UserDrug>(MaterialPageRoute(builder: (_) => CustomDrugScreen(existing: d)));

  Future<void> _editMemo(BuildContext context, WidgetRef ref, UserDrug d) async {
    final memo = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(title: '메모', initial: d.memo ?? '', hint: '예: 내과 처방, 아침 식후'),
    );
    if (memo == null) return;
    try {
      await ref.read(repositoryProvider).updateMyDrug(d.id, memo: memo.isEmpty ? null : memo);
      if (!context.mounted) return;
      ref.invalidate(myDrugsProvider);
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, UserDrug d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내 약에서 삭제할까요?'),
        content: Text('${d.itemName}\n이 약의 복용 시간표도 함께 삭제돼요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deleteMyDrug(d.id);
      if (!context.mounted) return;
      ref.invalidate(myDrugsProvider);
      ref.invalidate(schedulesProvider);
      ref.invalidate(intakesProvider(todayString()));
      ref.invalidate(daySummariesProvider); // 이번 주 줄·달력도 바로
      if (d.isCustom) {
        await deleteCustomPhoto(d.id); // 폰에 저장한 사진도 지움
        ref.invalidate(customPhotosProvider);
      }
      if (context.mounted) showSnack(context, '삭제했어요.');
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(myDrugsProvider);
    final photos = ref.watch(customPhotosProvider).valueOrNull ?? const <int, String>{};
    final hasCheckable = value.valueOrNull?.any((d) => !d.isCustom) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 약'),
        actions: [
          TextButton.icon(
            onPressed: () => addCustom(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('직접 추가'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncBody<List<UserDrug>>(
        value: value,
        onRetry: () => ref.invalidate(myDrugsProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyView(
              icon: Icons.medication_outlined,
              title: '등록한 약이 없어요',
              message: '"약 찾기" 탭에서 먹고 있는 약을 검색해 등록해 주세요.\n영양제는 직접 추가할 수 있어요.',
              action: OutlinedButton.icon(
                onPressed: () => addCustom(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('영양제·기타 직접 추가'),
              ),
            );
          }
          // 검색해서 등록한 약 → 직접 추가 항목 순서로 나눠 보여 줌
          final found = list.where((d) => !d.isCustom).toList();
          final custom = list.where((d) => d.isCustom).toList();
          return ListView(padding: const EdgeInsets.only(bottom: 100), children: [
            if (found.isNotEmpty) ...[
              _Header(title: '검색해서 등록한 약', count: found.length),
              for (final d in found) ...[_tile(context, ref, d, null), const Divider(height: 1)],
            ],
            if (custom.isNotEmpty) ...[
              _Header(
                title: '직접 추가',
                count: custom.length,
                note: '복용 시간·기록만 관리해요. 함께 먹어도 되는지 확인에는 들어가지 않아요.',
              ),
              for (final d in custom) ...[_tile(context, ref, d, photos[d.id]), const Divider(height: 1)],
            ],
          ]);
        },
      ),
      floatingActionButton: hasCheckable
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DurResultScreen())),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('함께 먹어도 되는지 확인', style: TextStyle(fontSize: 17)),
            )
          : null,
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, UserDrug d, String? photo) {
    final sub = [d.isCustom ? d.kind?.label : d.entpName, d.memo, d.periodLabel].whereType<String>().join(' · ');
    return ListTile(
      leading: d.isCustom ? CustomDrugThumb(path: photo, kind: d.kind) : DrugImage(url: d.imageUrl),
      title: DrugNameText(d.itemName, trailing: d.isCustom ? const CustomBadge() : null),
      subtitle: sub.isEmpty ? null : Text(sub),
      // 직접 추가 항목은 공공데이터 상세가 없으니 수정 화면으로
      onTap: d.isCustom
          ? () => _editCustom(context, ref, d)
          : () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => DrugDetailScreen(itemSeq: d.itemSeq))),
      trailing: PopupMenuButton<String>(
        tooltip: '더보기',
        onSelected: (v) => switch (v) {
          'edit' => _editCustom(context, ref, d),
          'memo' => _editMemo(context, ref, d),
          'period' => editDrugPeriod(context, ref, d),
          _ => _delete(context, ref, d),
        },
        itemBuilder: (_) => [
          if (d.isCustom) const PopupMenuItem(value: 'edit', child: Text('이름·종류·사진 수정')),
          const PopupMenuItem(value: 'memo', child: Text('메모 수정')),
          const PopupMenuItem(value: 'period', child: Text('복용 기간')),
          const PopupMenuItem(value: 'delete', child: Text('삭제')),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.count, this.note});
  final String title;
  final int count;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title  $count', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(keepWords(note!), style: t.bodySmall?.copyWith(fontSize: 13, color: Toss.grey600)),
        ],
      ]),
    );
  }
}
