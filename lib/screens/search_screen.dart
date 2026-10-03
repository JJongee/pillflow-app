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
  static const _pageSize = 20;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _query = '';
  final List<DrugSummary> _items = [];
  int _total = 0;
  int _page = 0;
  bool _loading = false; // 첫 페이지
  bool _loadingMore = false; // 다음 페이지
  Object? _error;
  int _generation = 0; // 검색어가 바뀌면 이전 응답은 버림

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // 끝에서 300px 남으면 다음 페이지
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // 지우기 버튼 즉시 표시
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
  }

  Future<void> _search(String v) async {
    final q = v.trim();
    final gen = ++_generation;
    setState(() {
      _query = q;
      _items.clear();
      _total = 0;
      _page = 0;
      _error = null;
      _loading = q.isNotEmpty;
      _loadingMore = false;
    });
    if (q.isEmpty) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      final r = await ref.read(repositoryProvider).searchDrugs(q, page: 1, size: _pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(r.items);
        _total = r.total;
        _page = 1;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _query.isEmpty) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final r = await ref.read(repositoryProvider).searchDrugs(_query, page: _page + 1, size: _pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(r.items);
        _total = r.total;
        _page += 1;
      });
    } catch (e) {
      if (mounted && gen == _generation) showSnack(context, e.toString());
    } finally {
      if (mounted && gen == _generation) setState(() => _loadingMore = false);
    }
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
            onSubmitted: (v) {
              _debounce?.cancel();
              _search(v);
            },
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
                        _debounce?.cancel();
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
    if (_query.isEmpty) {
      return const EmptyView(
        icon: Icons.medication_liquid_outlined,
        title: '먹고 있는 약을 검색해 보세요',
        message: '약 봉투나 상자에 적힌 이름으로 찾을 수 있어요.',
      );
    }
    if (_loading) return const LoadingView(message: '찾는 중이에요');
    if (_error != null) return ErrorView(error: _error!, onRetry: () => _search(_query));
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.search_off,
        title: '"$_query" 검색 결과가 없어요',
        message: '띄어쓰기 없이, 또는 이름 앞부분만 입력해 보세요.',
      );
    }
    final t = Theme.of(context).textTheme;
    // 0: 건수, 1..n: 결과, n+1: 하단(더 불러오는 중 / 끝)
    return ListView.separated(
      controller: _scroll,
      itemCount: _items.length + 2,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('$_total건', style: t.bodyMedium),
          );
        }
        if (i == _items.length + 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : _hasMore
                      ? OutlinedButton(onPressed: _loadMore, child: const Text('더 보기'))
                      : Text('검색 결과를 모두 봤어요', style: t.bodySmall),
            ),
          );
        }
        final d = _items[i - 1];
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
  }
}
