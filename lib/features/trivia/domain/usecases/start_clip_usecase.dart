import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class StartClipUseCase {
  const StartClipUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<void>> call({
    required String roundId,
    required int clipIndex,
  }) =>
      repository.startClip(roundId: roundId, clipIndex: clipIndex);
}
