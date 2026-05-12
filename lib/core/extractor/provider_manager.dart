import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/extractor_runner.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/models/detail_model.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/data/models/playback_model.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';

class ProviderManager {
  final DetailDataSource _detailDataSource;
  final HomeDataSource _homeDataSource;
  final SearchDataSource _searchDataSource;
  final ExtractorRunner _extractor;
  final HiveService _hiveService;
  final List<ProviderEntity> _providers = [];

  ProviderManager({
    required DetailDataSource detailDataSource,
    required HomeDataSource homeDataSource,
    required SearchDataSource searchDataSource,
    required ExtractorRunner extractor,
    required HiveService hiveService,
  })  : _detailDataSource = detailDataSource,
        _homeDataSource = homeDataSource,
        _searchDataSource = searchDataSource,
        _extractor = extractor,
        _hiveService = hiveService;

  void updateProviders(List<ProviderEntity> providers) {
    _providers
      ..clear()
      ..addAll(providers);
  }

  ProviderEntity? getProvider(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  String get currentProviderId => _hiveService.getCurrentProvider();

  bool _canExtract(ProviderEntity? info) =>
      info != null && info.mode != 'server' && info.extractor != null;

  bool _hasFullScope(ProviderEntity? info) =>
      _canExtract(info) && info!.extractor!.scope == 'all';

  Future<void> _ensureExtractorReady(ProviderEntity provider) async {
    await _extractor.loadRuntime();
    await _extractor.loadExtractor(provider.extractor!);
  }

  // ── Home ───────────────────────────────────────────────────────

  Future<Result<HomeDataEntity>> getHome({String? providerId}) async {
    final pid = providerId ?? currentProviderId;
    final info = getProvider(pid);
    if (_hasFullScope(info)) {
      return _extractorCall(info!, 'getHome', {}, HomeDataModel.fromJson);
    }
    return _serverCall(() => _homeDataSource.loadHome());
  }

  Future<Result<List<GenreEntity>>> getGenres() =>
      _serverCall(() => _homeDataSource.loadGenres());

  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) =>
      _serverCall(
        () => _homeDataSource.loadViewAll(type: key, slug: slug, page: page),
      );

  // ── Search ─────────────────────────────────────────────────────

  Future<Result<SearchEntity>> search({
    String? providerId,
    required String query,
    int page = 1,
  }) async {
    final pid = providerId ?? currentProviderId;
    final info = getProvider(pid);
    if (_hasFullScope(info)) {
      return _extractorCall(
        info!,
        'search',
        {'query': query, 'page': page},
        SearchModel.fromJson,
      );
    }
    return _serverCall(
      () => _searchDataSource.searchMovies(query, page: page),
    );
  }

  Future<Result<List<GenreEntity>>> searchGenres() =>
      _serverCall(() => _searchDataSource.getGenres());

  Future<Result<SearchEntity>> getMoviesByGenre(
    String genre, {
    int page = 1,
  }) =>
      _serverCall(
        () => _searchDataSource.getMoviesByGenre(genre, page: page),
      );

  // ── Detail ─────────────────────────────────────────────────────

  Future<Result<DetailEntity>> getDetail(
    String contentUrl, {
    String? provider,
  }) async {
    final pid = provider ?? currentProviderId;
    final info = getProvider(pid);
    if (_hasFullScope(info)) {
      return _extractorCall(
        info!,
        'getDetail',
        {'url': contentUrl},
        DetailModel.fromJson,
      );
    }
    return _serverCall(
      () => _detailDataSource.getDetail(contentUrl, provider: pid),
    );
  }

  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) async {
    final pid = provider ?? currentProviderId;
    final info = getProvider(pid);
    if (_hasFullScope(info)) {
      return _extractorCall(
        info!,
        'getEpisodes',
        {'url': contentUrl, 'page': page, 'size': size, 'sort': sort},
        PlaybackModel.fromJson,
      );
    }
    return _serverCall(
      () => _detailDataSource.getEpisodes(
        contentUrl,
        page: page,
        size: size,
        sort: sort,
        provider: pid,
      ),
    );
  }

  // ── Resolve Media ──────────────────────────────────────────────

  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    final info = getProvider(provider);
    if (_canExtract(info)) {
      final args = <String, dynamic>{'ref': ref};
      if (lang != null && lang.isNotEmpty) args['lang'] = lang;
      return _extractorCall(
        info!,
        'resolveMedia',
        args,
        MediaResolveModel.fromJson,
      );
    }
    return _serverCall(
      () => _detailDataSource.resolveMedia(
        ref: ref,
        provider: provider,
        lang: lang,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<Result<T>> _serverCall<T>(Future<T> Function() fn) async {
    try {
      return Success(await fn());
    } on DioException catch (e) {
      final raw = e.response?.data;
      final message =
          (raw is Map ? raw['message'] : null) ??
          e.message ??
          'Server xatolik';
      return Failure(Exception(message.toString()));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<T>> _extractorCall<T>(
    ProviderEntity provider,
    String method,
    Map<String, dynamic> args,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      await _ensureExtractorReady(provider);
      final json = await _extractor.call(
        provider.extractor!.name,
        method,
        args,
      );
      return Success(fromJson(json));
    } catch (e) {
      debugPrint('[ProviderManager] extractor $method error: $e');
      return Failure(Exception(e.toString()));
    }
  }

  void dispose() {
    _extractor.dispose();
  }
}
