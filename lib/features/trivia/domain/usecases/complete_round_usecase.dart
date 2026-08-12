import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class CompleteRoundUseCase {
  const CompleteRoundUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<TriviaResultEntity>> call(String roundId) =>
      repository.completeRound(roundId);
}
