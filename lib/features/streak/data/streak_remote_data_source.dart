import 'package:dio/dio.dart';

import 'package:soplay/features/streak/domain/entities/streak_state.dart';

class StreakRemoteDataSource {
  final Dio dio;
  const StreakRemoteDataSource({required this.dio});

  Future<StreakState> getMe(String timezone) async {
    final res = await dio.get(
      '/streak/me',
      queryParameters: {'timezone': timezone},
    );
    return StreakState.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StreakPingResult> ping(String timezone) async {
    final res = await dio.post(
      '/streak/ping',
      data: {'timezone': timezone},
    );
    return StreakPingResult.fromJson(res.data as Map<String, dynamic>);
  }
}
