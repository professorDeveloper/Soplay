import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/actor_fan_stat_entity.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';

class GetTopFansUseCase {
  const GetTopFansUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<ActorFanStatEntity>> call({
    required int actorId,
    required String kind,
  }) =>
      repository.getTopFans(actorId: actorId, kind: kind);
}
