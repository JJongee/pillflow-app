import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../data/providers.dart';
import '../widgets/dialogs.dart';

/// 설정: 태어난 해 · 데이터 출처 · 이용 안내 · 실행 모드 · 로그아웃
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('로그아웃')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final auth = ref.read(authTokenProvider.notifier);
    Navigator.of(context).popUntil((r) => r.isFirst); // 설정 화면 닫기
    auth.state = null; // → AuthGate 가 로그인 화면으로 전환
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final birthYear = ref.watch(birthYearProvider).valueOrNull;
    final t = Theme.of(context).textTheme;

    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(s, style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(children: [
        header('내 정보'),
        ListTile(
          leading: const Icon(Icons.cake_outlined),
          title: const Text('태어난 해'),
          subtitle: Text(birthYear == null ? '입력 안 함 · 연령금기를 확인하지 않아요' : '$birthYear년생'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => editBirthYear(context, ref, birthYear),
        ),
        header('데이터 출처'),
        const ListTile(
          leading: Icon(Icons.menu_book_outlined),
          title: Text('의약품 정보'),
          subtitle: Text('식품의약품안전처 의약품개요정보(e약은요)'),
        ),
        const ListTile(
          leading: Icon(Icons.fact_check_outlined),
          title: Text('병용금기 · 연령금기'),
          subtitle: Text('식품의약품안전처 DUR 품목리스트 (게시 2609)'),
        ),
        header('이용 안내'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '필플로우는 공공데이터를 안내하는 앱이며 진단이나 처방을 대신하지 않아요. '
            '공공데이터에 없는 약은 "판정 불가"로 표시되고, 이는 안전하다는 뜻이 아니에요. '
            '약을 바꾸거나 멈추기 전에 반드시 의사나 약사와 상담해 주세요.',
            style: t.bodyMedium,
          ),
        ),
        header('개발 정보'),
        ListTile(
          leading: const Icon(Icons.developer_mode_outlined),
          title: Text(AppConfig.useMock ? '목업 데이터 모드' : '서버 연결 모드'),
          subtitle: Text(AppConfig.useMock ? '서버 없이 assets/mock 데이터로 동작' : AppConfig.apiBase),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('로그아웃'),
          onTap: () => _logout(context, ref),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
