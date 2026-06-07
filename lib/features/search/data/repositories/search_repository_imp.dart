import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/repositories/search_repository.dart';

import '../datasources/search_data_source.dart';

class SearchRepositoryImp extends SearchRepository {
  final SearchDataSource dataSource;
  final JsRuntimeService? jsRuntime;
  final HiveService? hive;

  SearchRepositoryImp({
    required this.dataSource,
    this.jsRuntime,
    this.hive,
  });

  String? get _currentProvider {
    final id = hive?.getCurrentProvider();
    return (id == null || id.isEmpty) ? null : id;
  }

  @override
  Future<Result<List<GenreModel>>> getGenres() async {
    final provider = _currentProvider;
    if (provider != null && provider.startsWith('cs:')) {
      return const Success(<GenreModel>[]);
    }
    try {
      final result = await dataSource.getGenres();
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<SearchModel>> getMoviesByGenre(
    String genre, {
    int page = 1,
  }) async {
    try {
      final result = await dataSource.getMoviesByGenre(genre, page: page);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<SearchModel>> searchMovies(String query, {int page = 1}) async  {
    final js = jsRuntime;
    final provider = _currentProvider;
    if (provider != null && provider.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.search(provider.substring(3), query);
        if (map.isNotEmpty) return Success(SearchModel.fromJson(map));
        return Failure(Exception('CloudStream: no results'));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (js != null && provider != null) {
      try {
        final map = await js.trySearch(provider, query, page);
        if (map != null) return Success(SearchModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    try {
      final result = await dataSource.searchMovies(query, page: page);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
