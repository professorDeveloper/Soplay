import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/actor_profile_entity.dart';
import 'package:soplay/features/trivia/domain/repositories/trivia_repository.dart';

class GetActorProfileUseCase {
  const GetActorProfileUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<ActorProfileEntity>> call({
    required int id,
    required String kind,
  }) =>
      repository.getActorProfile(id: id, kind: kind);
}
