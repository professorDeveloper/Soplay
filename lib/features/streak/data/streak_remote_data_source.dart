import 'package:dio/dio.dart';

import 'package:soplay/features/streak/domain/entities/streak_state.dart';

class StreakRemoteDataSource {
  final Dio dio;
  const StreakRemoteDataSource({required this.dio});

  Future<StreakState> getMe(String timezone, int tzOffsetMinutes) async {
    final res = await dio.get(
      '/streak/me',
      queryParameters: {'timezone': timezone, 'tzOffset': tzOffsetMinutes},
    );
    return StreakState.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StreakPingResult> ping(String timezone, int tzOffsetMinutes) async {
    final res = await dio.post(
      '/streak/ping',
      data: {'timezone': timezone, 'tzOffset': tzOffsetMinutes},
    );
    return StreakPingResult.fromJson(res.data as Map<String, dynamic>);
  }
}
