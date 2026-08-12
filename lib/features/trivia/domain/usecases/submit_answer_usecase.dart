import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/reveal_result_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class SubmitAnswerUseCase {
  const SubmitAnswerUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<RevealResultEntity>> call({
    required String roundId,
    required int clipIndex,
    String? chosenOptionId,
    required int clientElapsedMs,
  }) =>
      repository.submitAnswer(
        roundId: roundId,
        clipIndex: clipIndex,
        chosenOptionId: chosenOptionId,
        clientElapsedMs: clientElapsedMs,
      );
}
