import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';

class DrugDetailScreen extends ConsumerStatefulWidget {
  const DrugDetailScreen({super.key, required this.itemSeq});
  final String itemSeq;

  @override
  ConsumerState<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends ConsumerState<DrugDetailScreen> {
  bool _saving = false;

  Future<void> _register(DrugDetail d) async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).addMyDrug(d.itemSeq);
      ref.invalidate(myDrugsProvider);
      if (mounted) showSnack(context, '내 약에 등록했어요.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(drugDetailProvider(widget.itemSeq));
    return Scaffold(
      appBar: AppBar(title: const Text('약 정보')),
      body: AsyncBody<DrugDetail>(
        value: value,
        onRetry: () => ref.invalidate(drugDetailProvider(widget.itemSeq)),
        data: (d) => ListView(padding: const EdgeInsets.all(16), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DrugImage(url: d.imageUrl, size: 96),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.itemName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(d.entpName ?? '', style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          InfoSection(title: '어디에 쓰나요', body: d.efficacy, initiallyExpanded: true),
          InfoSection(title: '어떻게 먹나요', body: d.useMethod),
          if (d.warning != null) InfoSection(title: '꼭 알아야 할 경고', body: d.warning),
          InfoSection(title: '주의사항', body: d.caution),
          InfoSection(title: '함께 먹으면 안 되는 것', body: d.interaction),
          InfoSection(title: '이상반응', body: d.sideEffect),
          InfoSection(title: '보관법', body: d.storage),
          const SizedBox(height: 8),
          Text(
            '출처: 식품의약품안전처 ${d.source ?? ''}'
            '${d.updateDate != null ? ' · 수정일 ${d.updateDate}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 96),
        ]),
      ),
      bottomNavigationBar: value.hasValue
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _register(value.requireValue),
                  icon: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  label: const Text('내 약에 등록'),
                ),
              ),
            )
          : null,
    );
  }
}
