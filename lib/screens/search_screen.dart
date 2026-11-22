import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';
import '../widgets/photo_search.dart';
import '../widgets/voice_search.dart';
import 'drug_detail_screen.dart';
import 'symptom_search_screen.dart';

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
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  int _generation = 0;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
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
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
  }

  /// 약 이름 검색 (첫 페이지). 증상 검색은 결과 위 버튼 → SymptomSearchScreen
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

  /// 아래로 내리면 다음 페이지
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
    } catch (_) {
      // 다음 페이지 실패는 조용히 넘어감 (다시 내리면 재시도)
    } finally {
      if (mounted && gen == _generation) setState(() => _loadingMore = false);
    }
  }

  Future<void> _voice() async {
    final q = await showVoiceSearch(context);
    if (!mounted || q == null || q.isEmpty) return;
    _debounce?.cancel();
    _controller.text = q;
    _search(q);
  }

  Future<void> _photo() async {
    final q = await showPhotoSearch(context, ref);
    if (!mounted || q == null || q.isEmpty) return;
    _debounce?.cancel();
    _controller.text = q;
    _search(q);
  }

  void _openSymptom(String q) {
    if (q.trim().isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SymptomSearchScreen(symptom: q.trim())));
  }

  @override
  Widget build(BuildContext context) {
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
              hintText: '약 이름이나 증상 (예: 타이레놀, 두통)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: '지우기',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _debounce?.cancel();
                      _controller.clear();
                      _search('');
                    },
                  ),
                IconButton(
                  tooltip: '사진으로 찾기',
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: _photo,
                ),
                IconButton(
                  tooltip: '말로 찾기',
                  icon: const Icon(Icons.mic),
                  onPressed: _voice,
                ),
              ]),
            ),
          ),
        ),
        Expanded(child: _results(mine)),
      ]),
    );
  }

  Widget _results(Set<String> mine) {
    if (_query.isEmpty) {
      return EmptyView(
        icon: Icons.medication_liquid_outlined,
        title: '어디가 아프신가요?',
        message: '약 이름이나 증상을 입력해 보세요.\n입력이 어려우면 말이나 사진으로 찾아도 돼요.',
        action: Column(children: [
          FilledButton.icon(
            onPressed: _voice,
            icon: const Icon(Icons.mic, size: 26),
            label: const Text('말로 약 찾기', style: TextStyle(fontSize: 18)),
            style: FilledButton.styleFrom(minimumSize: const Size(230, 56)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _photo,
            icon: const Icon(Icons.photo_camera_outlined, size: 26),
            label: const Text('사진으로 찾기', style: TextStyle(fontSize: 18)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(230, 56)),
          ),
        ]),
      );
    }
    if (_loading) return const LoadingView(message: '찾는 중이에요');
    if (_error != null) return ErrorView(error: _error!, onRetry: () => _search(_query));
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.search_off,
        title: '"$_query" 검색 결과가 없어요',
        message: '이름을 다시 확인하거나, 증상으로 찾아보세요.',
        action: FilledButton.icon(
          onPressed: () => _openSymptom(_query),
          icon: const Icon(Icons.manage_search),
          label: Text('효능/증상으로 "$_query" 약 찾기'),
        ),
      );
    }
    final t = Theme.of(context).textTheme;
    return ListView.separated(
      controller: _scroll,
      itemCount: _items.length + 2,
      separatorBuilder: (_, i) => i == 0 || i == _items.length ? const SizedBox.shrink() : const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(children: [
              Text('총 $_total건', style: t.bodyMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openSymptom(_query),
                icon: const Icon(Icons.manage_search, size: 20),
                label: const Text('증상(효능)으로 찾기'),
              ),
            ]),
          );
        }
        if (i == _items.length + 1) {
          return _loadingMore
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              : const SizedBox(height: 24);
        }
        final d = _items[i - 1];
        return ListTile(
          leading: DrugImage(url: d.imageUrl),
          title: DrugNameText(d.itemName),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(d.entpName ?? ''),
            if (d.rxRequired != null) Padding(padding: const EdgeInsets.only(top: 4), child: RxChip(rxRequired: d.rxRequired)),
          ]),
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