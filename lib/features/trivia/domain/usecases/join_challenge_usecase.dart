import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/trivia_round_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class JoinChallengeUseCase {
  const JoinChallengeUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<TriviaRoundEntity>> call(String code) =>
      repository.joinChallenge(code);
}
