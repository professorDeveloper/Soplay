import 'package:dio/dio.dart';
import 'package:soplay/features/trivia/data/models/actor_fan_stat_model.dart';
import 'package:soplay/features/trivia/data/models/actor_profile_model.dart';
import 'package:soplay/features/trivia/data/models/cast_person_model.dart';
import 'package:soplay/features/trivia/data/models/challenge_model.dart';
import 'package:soplay/features/trivia/data/models/leaderboard_entry_model.dart';
import 'package:soplay/features/trivia/data/models/reveal_result_model.dart';
import 'package:soplay/features/trivia/data/models/trivia_result_model.dart';
import 'package:soplay/features/trivia/data/models/trivia_round_model.dart';

class TriviaRemoteDataSource {
  const TriviaRemoteDataSource({required this.dio});

  final Dio dio;

  /// Buff is a fan checker over live actors only. The backend still accepts the
  /// retired 'klip_top' mode and the 'character' kind, but the app never sends
  /// them — [mode] and [kind] are accepted for signature compatibility and
  /// deliberately not forwarded.
  static const String _mode = 'fan_test';
  static const String _kind = 'person';

  // --- Rounds & gameplay -----------------------------------------------------

  Future<TriviaRoundModel> createRound({
    required String mode,
    int? actorId,
    String? kind,
    String? actorName,
    String? actorProfile,
  }) async {
    final body = <String, dynamic>{'mode': _mode, 'kind': _kind};
    if (actorId != null) body['actorId'] = actorId;
    // The server only stores these on insert — omitting them leaves the Top
    // Fans header with a blank name/avatar forever.
    if (actorName != null && actorName.isNotEmpty) body['actorName'] = actorName;
    if (actorProfile != null && actorProfile.isNotEmpty) {
      body['actorProfile'] = actorProfile;
    }

    final response = await dio.post('/trivia/rounds', data: body);
    return _round(response.data);
  }

  Future<void> startClip({
    required String roundId,
    required int clipIndex,
  }) async {
    await dio.post(
      '/trivia/rounds/$roundId/start-clip',
      data: <String, dynamic>{'clipIndex': clipIndex},
    );
  }

  Future<RevealResultModel> submitAnswer({
    required String roundId,
    required int clipIndex,
    String? chosenOptionId,
    required int clientElapsedMs,
  }) async {
    final response = await dio.post(
      '/trivia/rounds/$roundId/answers',
      data: <String, dynamic>{
        'clipIndex': clipIndex,
        'chosenOptionId': chosenOptionId,
        'clientElapsedMs': clientElapsedMs,
      },
    );
    final data = response.data;
    final payload = data is Map && data['reveal'] is Map
        ? data['reveal']
        : (data is Map && data['item'] is Map ? data['item'] : data);
    return RevealResultModel.fromJson(_asMap(payload));
  }

  Future<TriviaResultModel> completeRound(String roundId) async {
    final response = await dio.post('/trivia/rounds/$roundId/complete');
    final data = response.data;
    final payload = data is Map && data['result'] is Map ? data['result'] : data;
    return TriviaResultModel.fromJson(_asMap(payload));
  }

  Future<TriviaRoundModel> resumeRound(String roundId) async {
    final response = await dio.get('/trivia/rounds/$roundId');
    return _round(response.data);
  }

  // --- Cast / actors ---------------------------------------------------------

  Future<List<CastPersonModel>> searchCast({
    required String query,
    required String kind,
  }) async {
    final response = await dio.get(
      '/trivia/cast/search',
      queryParameters: <String, dynamic>{'q': query, 'kind': kind},
    );
    return _castList(response.data, kind);
  }

  Future<List<CastPersonModel>> getPopularCast({required String kind}) async {
    final response = await dio.get(
      '/trivia/cast/popular',
      queryParameters: <String, dynamic>{'kind': kind},
    );
    return _castList(response.data, kind);
  }

  Future<ActorProfileModel> getActorProfile({
    required int id,
    required String kind,
  }) async {
    final response = await dio.get(
      '/trivia/cast/$id',
      queryParameters: <String, dynamic>{'kind': kind},
    );
    final data = response.data;
    final payload = data is Map && data['item'] is Map
        ? data['item']
        : (data is Map && data['profile'] is Map ? data['profile'] : data);
    return ActorProfileModel.fromJson({'kind': kind, ..._asMap(payload)});
  }

  // --- Leaderboards & fandom -------------------------------------------------

  Future<List<LeaderboardEntryModel>> getLeaderboard({
    required String scope,
    String? mode,
    int? actorId,
  }) async {
    final params = <String, dynamic>{'scope': scope};
    if (mode != null && mode.isNotEmpty) params['mode'] = mode;
    if (actorId != null) params['actorId'] = actorId;

    final response = await dio.get('/trivia/leaderboard', queryParameters: params);
    final data = response.data;

    final rawItems = data is Map
        ? (data['items'] ?? data['entries'] ?? data['leaderboard'] ?? const [])
        : (data is List ? data : const []);

    final entries = (rawItems as List)
        .whereType<Map>()
        .map((e) => LeaderboardEntryModel.fromJson(e.cast<String, dynamic>()))
        .toList();

    // Pin "my rank" when the server returns it separately and it isn't already
    // present in the top-100 slice.
    final rawMe = data is Map ? (data['me'] ?? data['myRank']) : null;
    if (rawMe is Map) {
      final me = LeaderboardEntryModel.fromJson({..._asMap(rawMe), 'isMe': true});
      final present = entries.any((e) => e.userId == me.userId && me.userId.isNotEmpty);
      if (!present) entries.add(me);
    }

    return entries;
  }

  Future<ActorFanStatModel> getTopFans({
    required int actorId,
    required String kind,
  }) async {
    final response = await dio.get(
      '/trivia/actors/top-fans',
      queryParameters: <String, dynamic>{'actorId': actorId, 'kind': kind},
    );
    final data = response.data;
    final map = data is Map
        ? data.cast<String, dynamic>()
        : <String, dynamic>{'topFans': data is List ? data : const []};
    return ActorFanStatModel.fromJson({'actorId': actorId, 'kind': kind, ...map});
  }

  // --- Challenges ------------------------------------------------------------

  Future<ChallengeModel> createChallenge({
    String? mode,
    int? actorId,
    String? kind,
    String? roundId,
  }) async {
    final body = <String, dynamic>{};
    if (roundId != null && roundId.isNotEmpty) {
      body['roundId'] = roundId;
    } else {
      if (mode != null && mode.isNotEmpty) body['mode'] = mode;
      if (actorId != null) body['actorId'] = actorId;
      if (kind != null && kind.isNotEmpty) body['kind'] = kind;
    }

    final response = await dio.post('/trivia/challenges', data: body);
    return _challenge(response.data);
  }

  Future<ChallengeModel> getChallenge(String code) async {
    final response = await dio.get('/trivia/challenges/$code');
    return _challenge(response.data);
  }

  Future<TriviaRoundModel> joinChallenge(String code) async {
    final response = await dio.post('/trivia/challenges/$code/rounds');
    return _round(response.data);
  }

  // --- Parsing helpers -------------------------------------------------------

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  TriviaRoundModel _round(dynamic data) {
    final payload = data is Map && data['round'] is Map
        ? data['round']
        : (data is Map && data['item'] is Map ? data['item'] : data);
    return TriviaRoundModel.fromJson(_asMap(payload));
  }

  ChallengeModel _challenge(dynamic data) {
    final payload = data is Map && data['challenge'] is Map
        ? data['challenge']
        : (data is Map && data['item'] is Map ? data['item'] : data);
    return ChallengeModel.fromJson(_asMap(payload));
  }

  List<CastPersonModel> _castList(dynamic data, String kind) {
    final rawItems = data is Map
        ? (data['items'] ?? data['cards'] ?? data['results'] ?? const [])
        : (data is List ? data : const []);

    return (rawItems as List)
        .whereType<Map>()
        .map((e) => CastPersonModel.fromJson({'kind': kind, ...e.cast<String, dynamic>()}))
        .where((e) => e.id != 0)
        .toList(growable: false);
  }
}
