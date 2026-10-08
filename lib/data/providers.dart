import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/nav.dart';
import '../models/models.dart';
import 'api_repository.dart';
import 'mock_repository.dart';
import 'repository.dart';

/// 로그인 토큰. null 이면 로그인 화면이 보입니다.
/// 지금은 메모리에만 있어서 앱을 다시 켜면 다시 로그인합니다(시연용으로 충분).
final authTokenProvider = StateProvider<String?>((ref) => null);

/// 로그인 화면에 띄울 안내 (예: 로그인 만료)
final authNoticeProvider = StateProvider<String?>((ref) => null);

final repositoryProvider = Provider<PillRepository>(
  (ref) => AppConfig.useMock
      ? MockRepository()
      : ApiRepository(
          tokenProvider: () => ref.read(authTokenProvider),
          onUnauthorized: () {
            if (ref.read(authTokenProvider) == null) return; // 로그인 시도 중의 401은 '비밀번호 틀림'
            navigatorKey.currentState?.popUntil((r) => r.isFirst); // 열려 있던 화면 닫기
            ref.read(authNoticeProvider.notifier).state = '로그인이 만료됐어요. 다시 로그인해 주세요.';
            ref.read(authTokenProvider.notifier).state = null; // → AuthGate 가 로그인 화면으로
          },
        ),
);

final myDrugsProvider = FutureProvider.autoDispose<List<UserDrug>>(
  (ref) => ref.watch(repositoryProvider).getMyDrugs(),
);

final schedulesProvider = FutureProvider.autoDispose<List<ScheduleItem>>(
  (ref) => ref.watch(repositoryProvider).getSchedules(),
);

final drugDetailProvider = FutureProvider.autoDispose.family<DrugDetail, String>(
  (ref, itemSeq) => ref.watch(repositoryProvider).getDrug(itemSeq),
);

final intakesProvider = FutureProvider.autoDispose.family<List<IntakeRecord>, String>(
  (ref, date) => ref.watch(repositoryProvider).getIntakes(date),
);

final profileProvider = FutureProvider.autoDispose<Profile>(
  (ref) => ref.watch(repositoryProvider).getProfile(),
);

final durCheckProvider = FutureProvider.autoDispose<DurCheckResult>(
  (ref) => ref.watch(repositoryProvider).checkDur(),
);

String todayString() => DateTime.now().toIso8601String().substring(0, 10);
