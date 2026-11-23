import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../widgets/drug_widgets.dart';
import '../widgets/state_views.dart';
import 'drug_detail_screen.dart';

/// 증상(효능) 검색 결과: 설명서 효능에 [symptom]이 적힌 약 (추천 아님, 이름 가나다순)
/// - 아래로 내리면 20개씩 더 불러옴 ('두통'은 700개가 넘음)
/// - 약마다 처방 필요 / 처방 없이 구매 가능 표시
/// - 결과가 전부 전문의약품이면 위에 진료 안내
class SymptomSearchScreen extends ConsumerStatefulWidget {
  const SymptomSearchScreen({super.key, required this.symptom});
  final String symptom;

  @override
  ConsumerState<SymptomSearchScreen> createState() => _SymptomSearchScreenState();
}

class _SymptomSearchScreenState extends ConsumerState<SymptomSearchScreen> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final List<DrugSummary> _items = [];
  EfficacyPage? _first; // 첫 페이지 (전체 개수·일반/전문 개수)
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  bool get _hasMore => _first != null && _items.length < _first!.total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _first = null;
      _page = 0;
    });
    try {
      final r = await ref.read(repositoryProvider).searchByEfficacy(widget.symptom, page: 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _first = r;
        _items.addAll(r.items);
        _page = 1;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final r = await ref.read(repositoryProvider).searchByEfficacy(widget.symptom, page: _page + 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(r.items);
        _page += 1;
      });
    } catch (_) {
      // 다음 페이지 실패는 조용히 넘어감 (다시 내리면 재시도)
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myDrugsProvider).valueOrNull?.map((d) => d.itemSeq).toSet() ?? const <String>{};
    return Scaffold(
      appBar: AppBar(title: Text("효능에 '${widget.symptom}'이 들어간 약")),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Toss.grey100,
          child: Text(
            "추천이 아니라, 설명서의 효능에 '${widget.symptom}'이(가) 적힌 약을 보여 드려요. 고르기 전에 약사와 상의해 주세요.",
            style: const TextStyle(fontSize: 13, color: Toss.grey700),
          ),
        ),
        Expanded(child: _body(mine)),
      ]),
    );
  }

  Widget _body(Set<String> mine) {
    if (_loading) return const LoadingView(message: '약 목록을 불러오는 중이에요');
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final first = _first!;
    if (_items.isEmpty) {
      return const EmptyView(
        icon: Icons.search_off,
        title: '검색 결과가 없어요',
        message: '다른 말로 검색해 보세요.',
      );
    }
    final t = Theme.of(context).textTheme;
    return ListView.separated(
      controller: _scroll,
      itemCount: _items.length + 2,
      separatorBuilder: (_, i) => i == 0 || i == _items.length ? const SizedBox.shrink() : const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (first.onlyRx) _OnlyRxNotice(count: first.rxCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text('총 ${first.total}건 · 이름순', style: t.bodyMedium),
            ),
          ]);
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
            if (d.rxRequired != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: RxChip(rxRequired: d.rxRequired)),
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

/// 결과가 전부 전문의약품일 때: 처방 필요 = 주황 (빨강은 금기에만)
class _OnlyRxNotice extends StatelessWidget {
  const _OnlyRxNotice({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.cautionBg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.local_hospital_outlined, color: AppColors.caution),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '찾은 약 $count개가 모두 의사의 처방이 있어야 살 수 있는 약이에요. 이 증상이 있다면 먼저 병원 진료를 받아 보세요.',
              style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.caution, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
}
