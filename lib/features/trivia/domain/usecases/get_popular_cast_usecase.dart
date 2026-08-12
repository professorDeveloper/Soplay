import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class GetPopularCastUseCase {
  const GetPopularCastUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<List<CastPersonEntity>>> call({required String kind}) =>
      repository.getPopularCast(kind: kind);
}
