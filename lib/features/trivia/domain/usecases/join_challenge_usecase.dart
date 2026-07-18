import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';

class JoinChallengeUseCase {
  const JoinChallengeUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<TriviaRoundEntity>> call(String code) =>
      repository.joinChallenge(code);
}
