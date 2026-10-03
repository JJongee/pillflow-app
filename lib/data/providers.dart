import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../models/models.dart';
import 'api_repository.dart';
import 'mock_repository.dart';
import 'repository.dart';

final repositoryProvider = Provider<PillRepository>(
  (ref) => AppConfig.useMock ? MockRepository() : ApiRepository(),
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

final birthYearProvider = FutureProvider.autoDispose<int?>(
  (ref) => ref.watch(repositoryProvider).getBirthYear(),
);

final durCheckProvider = FutureProvider.autoDispose<DurCheckResult>(
  (ref) => ref.watch(repositoryProvider).checkDur(),
);

String todayString() => DateTime.now().toIso8601String().substring(0, 10);
