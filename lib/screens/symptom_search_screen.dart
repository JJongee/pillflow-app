import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';
import 'drug_detail_screen.dart';

class SymptomSearchScreen extends ConsumerStatefulWidget {
  final String symptom;

  const SymptomSearchScreen({super.key, required this.symptom});

  @override
  ConsumerState<SymptomSearchScreen> createState() => _SymptomSearchScreenState();
}

class _SymptomSearchScreenState extends ConsumerState<SymptomSearchScreen> {
  late Future<List<DrugSummary>> _searchFuture;

  @override
  void initState() {
    super.initState();
    _fetchSearch();
  }

  void _fetchSearch() {
    _searchFuture = ref.read(repositoryProvider).searchByEfficacy(widget.symptom);
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myDrugsProvider).valueOrNull?.map((d) => d.itemSeq).toSet() ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: Text("효능에 '${widget.symptom}'이 들어간 약")),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Toss.grey100,
            child: Text(
              "추천이 아니라, 설명서의 효능에 '${widget.symptom}'이(가) 적힌 약을 보여 드려요. 고르기 전에 약사와 상의해 주세요.",
              style: const TextStyle(fontSize: 13, color: Toss.grey700),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<DrugSummary>>(
              future: _searchFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView(message: '약 목록을 불러오는 중이에요');
                }
                if (snapshot.hasError) {
                  return ErrorView(
                    error: snapshot.error!,
                    onRetry: () {
                      setState(() {
                        _fetchSearch();
                      });
                    },
                  );
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const EmptyView(
                    icon: Icons.search_off,
                    title: '검색 결과가 없어요',
                    message: '다른 검색어로 시도해 보세요.',
                  );
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = items[i];
                    return ListTile(
                      leading: DrugImage(url: d.imageUrl),
                      title: Text(d.itemName),
                      subtitle: Text(d.entpName ?? ''),
                      trailing: mine.contains(d.itemSeq)
                          ? const Chip(
                              label: Text('등록됨', style: TextStyle(fontSize: 13)),
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(Icons.check, size: 16),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => DrugDetailScreen(itemSeq: d.itemSeq)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}