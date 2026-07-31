import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';

class CompleteRoundUseCase {
  const CompleteRoundUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<TriviaResultEntity>> call(String roundId) =>
      repository.completeRound(roundId);
}
