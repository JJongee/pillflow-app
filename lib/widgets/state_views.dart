import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 로딩 · 빈 결과 · 오류 상태 공통 위젯 (체크리스트: 로딩·빈 결과·오류 상태 설계)

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = '불러오는 중이에요'});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ]),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: Colors.black38),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.error_outline,
        title: '문제가 생겼어요',
        message: error.toString(),
        action: onRetry == null
            ? null
            : FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('다시 시도')),
      );
}

/// AsyncValue 를 로딩/오류/데이터로 나눠 그려 주는 도우미
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        // 스크롤 가능하게 감싸서 RefreshIndicator 안에서도 당겨서 새로고침이 됩니다.
        loading: () => const _Scrollable(child: LoadingView()),
        error: (e, _) => _Scrollable(child: ErrorView(error: e, onRetry: onRetry)),
      );
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: c.maxHeight), child: child),
        ),
      );
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 17))));
}
