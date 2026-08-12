import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/challenge_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class CreateChallengeUseCase {
  const CreateChallengeUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<ChallengeEntity>> call({
    String? mode,
    int? actorId,
    String? kind,
    String? roundId,
  }) =>
      repository.createChallenge(
        mode: mode,
        actorId: actorId,
        kind: kind,
        roundId: roundId,
      );
}
