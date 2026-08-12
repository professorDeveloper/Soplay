import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/challenge_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class GetChallengeUseCase {
  const GetChallengeUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<ChallengeEntity>> call(String code) =>
      repository.getChallenge(code);
}
