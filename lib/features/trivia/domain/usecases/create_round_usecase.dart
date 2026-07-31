import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';

class CreateRoundUseCase {
  const CreateRoundUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<TriviaRoundEntity>> call({
    required String mode,
    int? actorId,
    String? kind,
  }) =>
      repository.createRound(mode: mode, actorId: actorId, kind: kind);
}
