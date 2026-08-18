import 'package:dio/dio.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';

import '../model/search_model.dart';

class SearchDataSource {
  final Dio dio;

  SearchDataSource({required this.dio});

  Future<List<GenreModel>> getGenres() async {
    var response = await dio.get('/contents/genres');
    return (response.data['items'] as List)
        .map((e) => GenreModel.fromJson(e))
        .toList();
  }

  Future<SearchModel> getMoviesByGenre(String genre, {int page = 1}) async {
    var response = await dio.get(
      '/contents/genre/$genre',
      queryParameters: {'page': page},
    );
    return SearchModel.fromJson(response.data);
  }

  Future<SearchModel> getMoviesByCountry(String country, {int page = 1}) async {
    var response = await dio.get(
      '/contents/country/$country',
      queryParameters: {'page': page},
    );
    return SearchModel.fromJson(response.data);
  }

  /// [provider] overrides the interceptor's "current provider", which is what
  /// lets cross-search treat each selected server provider as its own leg
  /// instead of collapsing them into one.
  Future<SearchModel> searchMovies(
    String query, {
    int page = 1,
    String? provider,
  }) async {
    var response = await dio.get(
      '/contents/search',
      queryParameters: {
        'q': query,
        'page': page,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    return SearchModel.fromJson(response.data);
  }
}
