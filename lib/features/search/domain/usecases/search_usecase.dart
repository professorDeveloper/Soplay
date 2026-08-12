import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/search/domain/entities/search_entity.dart';

import '../repositories/search_repository.dart';

class SearchUseCase {
  final SearchRepository repository;

  SearchUseCase({required this.repository});

  Future<Result<SearchEntity>> call(String query, {int page = 1}) =>
      repository.searchMovies(query, page: page);
}
