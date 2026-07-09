import 'package:dio/dio.dart';

import 'package:soplay/features/watch_party/domain/entities/party_content.dart';

/// Thin REST layer for watch party rooms. Mirrors `StreakRemoteDataSource`:
/// a single injected [Dio] whose baseUrl already ends with `/api`.
class WatchPartyRemoteDataSource {
  final Dio dio;
  const WatchPartyRemoteDataSource({required this.dio});

  /// `POST /watch-party` → `{ code, party }`.
  Future<Map<String, dynamic>> createParty({PartyContent? content}) async {
    final res = await dio.post(
      '/watch-party',
      data: <String, dynamic>{
        if (content != null) 'content': content.toJson(),
      },
    );
    return _asMap(res.data);
  }

  /// `GET /watch-party/:code` — flat room preview for the join screen.
  Future<Map<String, dynamic>> preview(String code) async {
    final res = await dio.get('/watch-party/$code');
    return _asMap(res.data);
  }

  /// `POST /watch-party/:code/invite` `{ userId }` (host only).
  Future<void> invite(String code, String userId) async {
    await dio.post(
      '/watch-party/$code/invite',
      data: <String, dynamic>{'userId': userId},
    );
  }

  /// `DELETE /watch-party/:code` (host only).
  Future<void> close(String code) async {
    await dio.delete('/watch-party/$code');
  }

  static Map<String, dynamic> _asMap(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}
