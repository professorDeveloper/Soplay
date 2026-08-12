import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:riasdxd/features/trivia/domain/repositories/trivia_repository.dart';

class SearchCastUseCase {
  const SearchCastUseCase(this.repository);

  final TriviaRepository repository;

  Future<Result<List<CastPersonEntity>>> call({
    required String query,
    required String kind,
  }) =>
      repository.searchCast(query: query, kind: kind);
}
