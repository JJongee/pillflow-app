import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/dialogs.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';
import 'drug_detail_screen.dart';
import 'dur_result_screen.dart';

class MyDrugsScreen extends ConsumerWidget {
  const MyDrugsScreen({super.key});

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
      if (context.mounted) showSnack(context, '삭제했어요.');
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(myDrugsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('내 약')),
      body: AsyncBody<List<UserDrug>>(
        value: value,
        onRetry: () => ref.invalidate(myDrugsProvider),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.medication_outlined,
              title: '등록한 약이 없어요',
              message: '"약 찾기" 탭에서 먹고 있는 약을 검색해 등록해 주세요.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = list[i];
              return ListTile(
                leading: DrugImage(url: d.imageUrl),
                title: Text(d.itemName),
                subtitle: Text([d.entpName, d.memo].whereType<String>().join(' · ')),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => DrugDetailScreen(itemSeq: d.itemSeq))),
                trailing: PopupMenuButton<String>(
                  tooltip: '더보기',
                  onSelected: (v) => v == 'memo' ? _editMemo(context, ref, d) : _delete(context, ref, d),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'memo', child: Text('메모 수정')),
                    PopupMenuItem(value: 'delete', child: Text('삭제')),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: (value.valueOrNull?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DurResultScreen())),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('함께 먹어도 되는지 확인', style: TextStyle(fontSize: 17)),
            )
          : null,
    );
  }
}
