import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';
import 'drug_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<Paged<DrugSummary>>? _future;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // 지우기 버튼 즉시 표시
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
  }

  void _search(String v) {
    final q = v.trim();
    setState(() {
      _query = q;
      _future = q.isEmpty ? null : ref.read(repositoryProvider).searchDrugs(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 이미 등록한 약은 검색 결과에 "등록됨" 표시
    final mine = ref.watch(myDrugsProvider).valueOrNull?.map((d) => d.itemSeq).toSet() ?? const <String>{};
    return Scaffold(
        appBar: AppBar(title: const Text('약 찾기')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 19),
              decoration: InputDecoration(
                hintText: '약 이름을 입력하세요 (예: 타이레놀)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '지우기',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _search('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(child: _results(mine)),
        ]),
      );
  }

  Widget _results(Set<String> mine) {
    if (_future == null) {
      return const EmptyView(
        icon: Icons.medication_liquid_outlined,
        title: '먹고 있는 약을 검색해 보세요',
        message: '약 봉투나 상자에 적힌 이름으로 찾을 수 있어요.',
      );
    }
    return FutureBuilder<Paged<DrugSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingView(message: '찾는 중이에요');
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: () => _search(_query));
        final page = snap.data!;
        if (page.items.isEmpty) {
          return EmptyView(
            icon: Icons.search_off,
            title: '"$_query" 검색 결과가 없어요',
            message: '띄어쓰기 없이, 또는 이름 앞부분만 입력해 보세요.',
          );
        }
        return ListView.separated(
          itemCount: page.items.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('${page.total}건', style: Theme.of(context).textTheme.bodyMedium),
              );
            }
            final d = page.items[i - 1];
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
    );
  }
}
