import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/reveal_result_entity.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';

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
