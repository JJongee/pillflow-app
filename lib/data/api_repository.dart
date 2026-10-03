import 'package:dio/dio.dart';

import '../core/config.dart';
import '../models/models.dart';
import 'repository.dart';

/// 실제 서버용 구현. 경로와 필드는 docs/api_contract.md 와 같습니다.
/// 10/5 실제 API 연동 때 주연우 님 서버와 맞춰 보면서 고치면 됩니다.
class ApiRepository implements PillRepository {
  ApiRepository({Dio? dio, this.tokenProvider})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBase,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final t = tokenProvider?.call();
      if (t != null) o.headers['Authorization'] = 'Bearer $t';
      h.next(o);
    }));
  }

  final Dio _dio;

  /// 인증이 붙으면 토큰을 돌려주는 함수를 넘기세요.
  final String? Function()? tokenProvider;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        throw RepoException(data['detail'] as String, code: data['code'] as String?);
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw RepoException('서버에 연결할 수 없어요. 서버가 켜져 있는지 확인해 주세요.', code: 'NETWORK');
      }
      throw RepoException('요청을 처리하지 못했어요. (${e.response?.statusCode ?? '-'})');
    } on TypeError {
      // 서버 응답 필드가 api_contract.md 와 다를 때
      throw RepoException('서버 응답 형식이 예상과 달라요. API 명세를 확인해 주세요.', code: 'BAD_RESPONSE');
    }
  }

  List<Map<String, dynamic>> _list(dynamic d) => (d as List).cast<Map<String, dynamic>>();

  @override
  Future<Paged<DrugSummary>> searchDrugs(String query, {int page = 1, int size = 20}) => _call(() async {
        final r = await _dio.get('/drugs', queryParameters: {'q': query, 'page': page, 'size': size});
        final j = r.data as Map<String, dynamic>;
        return Paged(
          items: _list(j['items']).map(DrugSummary.fromJson).toList(),
          page: j['page'] as int,
          size: j['size'] as int,
          total: j['total'] as int,
        );
      });

  @override
  Future<DrugDetail> getDrug(String itemSeq) => _call(() async {
        final r = await _dio.get('/drugs/$itemSeq');
        return DrugDetail.fromJson(r.data as Map<String, dynamic>);
      });

  @override
  Future<List<UserDrug>> getMyDrugs() => _call(() async {
        final r = await _dio.get('/me/drugs');
        return _list(r.data).map(UserDrug.fromJson).toList();
      });

  @override
  Future<UserDrug> addMyDrug(String itemSeq, {String? memo}) => _call(() async {
        final r = await _dio.post('/me/drugs', data: {'item_seq': itemSeq, 'memo': memo});
        return UserDrug.fromJson(r.data as Map<String, dynamic>);
      });

  @override
  Future<UserDrug> updateMyDrug(int id, {String? memo}) => _call(() async {
        final r = await _dio.patch('/me/drugs/$id', data: {'memo': memo});
        return UserDrug.fromJson(r.data as Map<String, dynamic>);
      });

  @override
  Future<void> deleteMyDrug(int id) => _call(() async {
        await _dio.delete('/me/drugs/$id');
      });

  @override
  Future<List<ScheduleItem>> getSchedules() => _call(() async {
        final r = await _dio.get('/me/schedules');
        return _list(r.data).map(ScheduleItem.fromJson).toList();
      });

  @override
  Future<ScheduleItem> addSchedule({
    required int userDrugId,
    required String time,
    required MealRelation mealRelation,
    String? doseText,
  }) =>
      _call(() async {
        final r = await _dio.post('/me/schedules', data: {
          'user_drug_id': userDrugId,
          'time': time,
          'meal_relation': mealRelation.code,
          'dose_text': doseText,
        });
        return ScheduleItem.fromJson(r.data as Map<String, dynamic>);
      });

  @override
  Future<void> deleteSchedule(int id) => _call(() async {
        await _dio.delete('/me/schedules/$id');
      });

  @override
  Future<List<IntakeRecord>> getIntakes(String date) => _call(() async {
        final r = await _dio.get('/me/intakes', queryParameters: {'date': date});
        return _list(r.data).map(IntakeRecord.fromJson).toList();
      });

  @override
  Future<void> setIntake({required int scheduleId, required String date, required IntakeStatus status}) =>
      _call(() async {
        await _dio.put('/me/intakes', data: {'schedule_id': scheduleId, 'date': date, 'status': status.code});
      });

  @override
  Future<int?> getBirthYear() => _call(() async {
        final r = await _dio.get('/me/profile');
        return (r.data as Map<String, dynamic>)['birth_year'] as int?;
      });

  @override
  Future<void> setBirthYear(int? year) => _call(() async {
        await _dio.put('/me/profile', data: {'birth_year': year});
      });

  @override
  Future<DurCheckResult> checkDur({List<String>? itemSeqs}) => _call(() async {
        final r = await _dio.post('/dur/check', data: {if (itemSeqs != null) 'item_seqs': itemSeqs});
        return DurCheckResult.fromJson(r.data as Map<String, dynamic>);
      });
}
