import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/actor_fan_stat_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/actor_profile_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/challenge_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/reveal_result_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/trivia_round_entity.dart';

abstract class TriviaRepository {
  // --- Rounds & gameplay -----------------------------------------------------
  Future<Result<TriviaRoundEntity>> createRound({
    required String mode,
    int? actorId,
    String? kind,
  });

  Future<Result<void>> startClip({
    required String roundId,
    required int clipIndex,
  });

  Future<Result<RevealResultEntity>> submitAnswer({
    required String roundId,
    required int clipIndex,
    String? chosenOptionId,
    required int clientElapsedMs,
  });

  Future<Result<TriviaResultEntity>> completeRound(String roundId);

  Future<Result<TriviaRoundEntity>> resumeRound(String roundId);

  // --- Cast / actors ---------------------------------------------------------
  Future<Result<List<CastPersonEntity>>> searchCast({
    required String query,
    required String kind,
  });

  Future<Result<List<CastPersonEntity>>> getPopularCast({required String kind});

  Future<Result<ActorProfileEntity>> getActorProfile({
    required int id,
    required String kind,
  });

  // --- Leaderboards & fandom -------------------------------------------------
  Future<Result<List<LeaderboardEntryEntity>>> getLeaderboard({
    required String scope,
    String? mode,
    int? actorId,
  });

  Future<Result<ActorFanStatEntity>> getTopFans({
    required int actorId,
    required String kind,
  });

  // --- Challenges ------------------------------------------------------------
  Future<Result<ChallengeEntity>> createChallenge({
    String? mode,
    int? actorId,
    String? kind,
    String? roundId,
  });

  Future<Result<ChallengeEntity>> getChallenge(String code);

  Future<Result<TriviaRoundEntity>> joinChallenge(String code);
}
