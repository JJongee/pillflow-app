import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'core/nav.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'screens/intake_screen.dart';
import 'screens/login_screen.dart';
import 'screens/my_drugs_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/search_screen.dart';

class PillFlowApp extends StatelessWidget {
  const PillFlowApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '필플로우',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AuthGate(),
      );
}

/// 로그인 전이면 로그인 화면, 로그인 후면 홈
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(authTokenProvider) == null
          ? LoginScreen(initialError: ref.watch(authNoticeProvider))
          : const HomeShell();
}

/// 하단 탭 4개: 오늘 · 약 찾기 · 내 약 · 시간표
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    IntakeScreen(),
    SearchScreen(),
    MyDrugsScreen(),
    ScheduleScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          if (AppConfig.useMock)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3CD),
              padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 4, 12, 4),
              child: const Text('목업 데이터로 실행 중', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
            ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: AppConfig.useMock,
              // 바깥 Scaffold가 이미 키보드만큼 줄여 주므로, 탭 안 Scaffold가 한 번 더 줄이지 않게
              // (실기기에서 키보드를 열면 검색창이 사라지던 문제)
              child: Builder(
                builder: (context) => MediaQuery.removeViewInsets(
                  context: context,
                  removeBottom: true,
                  child: IndexedStack(index: _index, children: _pages),
                ),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          height: 72,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: '오늘'),
            NavigationDestination(icon: Icon(Icons.search), label: '약 찾기'),
            NavigationDestination(
                icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication), label: '내 약'),
            NavigationDestination(
                icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: '시간표'),
          ],
        ),
      );
}
