import 'package:dio/dio.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/data/datasources/trivia_remote_data_source.dart';
import 'package:soplay/features/trivia/domain/entities/actor_fan_stat_entity.dart';
import 'package:soplay/features/trivia/domain/entities/actor_profile_entity.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/domain/entities/challenge_entity.dart';
import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:soplay/features/trivia/domain/entities/reveal_result_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';
import 'package:soplay/features/trivia/domain/trivia_failure.dart';

class TriviaRepositoryImpl implements TriviaRepository {
  const TriviaRepositoryImpl(this.dataSource);

  final TriviaRemoteDataSource dataSource;

  @override
  Future<Result<TriviaRoundEntity>> createRound({
    required String mode,
    int? actorId,
    String? kind,
  }) async {
    try {
      return Success(
        await dataSource.createRound(mode: mode, actorId: actorId, kind: kind),
      );
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<void>> startClip({
    required String roundId,
    required int clipIndex,
  }) async {
    try {
      await dataSource.startClip(roundId: roundId, clipIndex: clipIndex);
      return Success<void>(null);
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<RevealResultEntity>> submitAnswer({
    required String roundId,
    required int clipIndex,
    String? chosenOptionId,
    required int clientElapsedMs,
  }) async {
    try {
      return Success(
        await dataSource.submitAnswer(
          roundId: roundId,
          clipIndex: clipIndex,
          chosenOptionId: chosenOptionId,
          clientElapsedMs: clientElapsedMs,
        ),
      );
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<TriviaResultEntity>> completeRound(String roundId) async {
    try {
      return Success(await dataSource.completeRound(roundId));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<TriviaRoundEntity>> resumeRound(String roundId) async {
    try {
      return Success(await dataSource.resumeRound(roundId));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<List<CastPersonEntity>>> searchCast({
    required String query,
    required String kind,
  }) async {
    try {
      return Success(await dataSource.searchCast(query: query, kind: kind));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<List<CastPersonEntity>>> getPopularCast({
    required String kind,
  }) async {
    try {
      return Success(await dataSource.getPopularCast(kind: kind));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<ActorProfileEntity>> getActorProfile({
    required int id,
    required String kind,
  }) async {
    try {
      return Success(await dataSource.getActorProfile(id: id, kind: kind));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<List<LeaderboardEntryEntity>>> getLeaderboard({
    required String scope,
    String? mode,
    int? actorId,
  }) async {
    try {
      return Success(
        await dataSource.getLeaderboard(scope: scope, mode: mode, actorId: actorId),
      );
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<ActorFanStatEntity>> getTopFans({
    required int actorId,
    required String kind,
  }) async {
    try {
      return Success(await dataSource.getTopFans(actorId: actorId, kind: kind));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<ChallengeEntity>> createChallenge({
    String? mode,
    int? actorId,
    String? kind,
    String? roundId,
  }) async {
    try {
      return Success(
        await dataSource.createChallenge(
          mode: mode,
          actorId: actorId,
          kind: kind,
          roundId: roundId,
        ),
      );
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<ChallengeEntity>> getChallenge(String code) async {
    try {
      return Success(await dataSource.getChallenge(code));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<TriviaRoundEntity>> joinChallenge(String code) async {
    try {
      return Success(await dataSource.joinChallenge(code));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  /// Keeps the status alongside the message so the presentation layer can tell
  /// "this actor has too few approved clips" (409) from a real server fault and
  /// render its own localized copy instead of echoing the server's English.
  TriviaFailure _failureFrom(DioException e) => TriviaFailure(
        status: e.response?.statusCode,
        message: _messageFrom(e),
      );

  String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.first.toString();
    }
    return e.message ?? 'Something went wrong';
  }
}
