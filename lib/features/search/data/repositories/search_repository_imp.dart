import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';
import 'package:soplay/features/search/domain/repositories/search_repository.dart';

class SearchRepositoryImp extends SearchRepository {
  final ProviderManager providerManager;

  SearchRepositoryImp({required this.providerManager});

  @override
  Future<Result<List<GenreEntity>>> getGenres() =>
      providerManager.searchGenres();

  @override
  Future<Result<SearchEntity>> getMoviesByGenre(
    String genre, {
    int page = 1,
  }) =>
      providerManager.getMoviesByGenre(genre, page: page);

  @override
  Future<Result<SearchEntity>> searchMovies(String query, {int page = 1}) =>
      providerManager.search(query: query, page: page);
}
