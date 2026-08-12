import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class GetLeaderboardUseCase {
  const GetLeaderboardUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<List<LeaderboardEntryEntity>>> call({
    required String scope,
    String? mode,
    int? actorId,
  }) =>
      repository.getLeaderboard(scope: scope, mode: mode, actorId: actorId);
}
