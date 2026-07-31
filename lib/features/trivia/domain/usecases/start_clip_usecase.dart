import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';

class StartClipUseCase {
  const StartClipUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<void>> call({
    required String roundId,
    required int clipIndex,
  }) =>
      repository.startClip(roundId: roundId, clipIndex: clipIndex);
}
