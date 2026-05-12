import 'package:flutter/foundation.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/extractor_runner.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';

class ProviderManager {
  final DetailDataSource _detailDataSource;
  final HomeDataSource _homeDataSource;
  final SearchDataSource _searchDataSource;
  final ExtractorRunner _extractor;
  final List<ProviderEntity> _providers = [];

  ProviderManager({
    required DetailDataSource detailDataSource,
    required HomeDataSource homeDataSource,
    required SearchDataSource searchDataSource,
    required ExtractorRunner extractor,
  })  : _detailDataSource = detailDataSource,
        _homeDataSource = homeDataSource,
        _searchDataSource = searchDataSource,
        _extractor = extractor;

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

  bool isServerMode(String providerId) {
    final provider = getProvider(providerId);
    return provider == null || provider.mode == 'server';
  }

  /// Runtime + extractor ni tayyorlaydi (agar kerak bo'lsa)
  Future<void> _ensureExtractorReady(ProviderEntity provider) async {
    await _extractor.loadRuntime();
    await _extractor.loadExtractor(provider.extractor!);
  }

  // --- Resolve Media ---

  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    final providerInfo = getProvider(provider);

    if (providerInfo == null ||
        providerInfo.mode == 'server' ||
        providerInfo.extractor == null) {
      return _resolveViaServer(ref: ref, provider: provider, lang: lang);
    }

    return _resolveViaExtractor(
      providerInfo: providerInfo,
      ref: ref,
      lang: lang,
    );
  }

  Future<Result<MediaResolveEntity>> _resolveViaServer({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    try {
      final result = await _detailDataSource.resolveMedia(
        ref: ref,
        provider: provider,
        lang: lang,
      );
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<MediaResolveEntity>> _resolveViaExtractor({
    required ProviderEntity providerInfo,
    required String ref,
    String? lang,
  }) async {
    try {
      await _ensureExtractorReady(providerInfo);

      final args = <String, dynamic>{'ref': ref};
      if (lang != null && lang.isNotEmpty) args['lang'] = lang;

      final json = await _extractor.call(
        providerInfo.extractor!.name,
        'resolveMedia',
        args,
      );
      final result = MediaResolveModel.fromJson(json);
      return Success(result);
    } catch (e) {
      debugPrint('[ProviderManager] extractor resolveMedia error: $e');
      return Failure(Exception('Extractor xatolik: ${e.toString()}'));
    }
  }

  // --- Home ---

  Future<Result<HomeDataEntity>> getHome(String providerId) async {
    final providerInfo = getProvider(providerId);

    if (providerInfo != null &&
        providerInfo.mode == 'client' &&
        providerInfo.extractor != null &&
        providerInfo.extractor!.scope == 'all') {
      return _getHomeViaExtractor(providerInfo);
    }

    return _getHomeViaServer();
  }

  Future<Result<HomeDataEntity>> _getHomeViaServer() async {
    try {
      final result = await _homeDataSource.loadHome();
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<HomeDataEntity>> _getHomeViaExtractor(
    ProviderEntity providerInfo,
  ) async {
    try {
      await _ensureExtractorReady(providerInfo);

      final json = await _extractor.call(
        providerInfo.extractor!.name,
        'getHome',
        {},
      );
      final result = HomeDataModel.fromJson(json);
      return Success(result);
    } catch (e) {
      debugPrint('[ProviderManager] extractor getHome error: $e');
      return Failure(Exception('Extractor xatolik: ${e.toString()}'));
    }
  }

  // --- Search ---

  Future<Result<SearchEntity>> search({
    required String providerId,
    required String query,
    int page = 1,
  }) async {
    final providerInfo = getProvider(providerId);

    if (providerInfo != null &&
        providerInfo.mode == 'client' &&
        providerInfo.extractor != null &&
        providerInfo.extractor!.scope == 'all') {
      return _searchViaExtractor(providerInfo, query, page);
    }

    return _searchViaServer(query, page);
  }

  Future<Result<SearchEntity>> _searchViaServer(String query, int page) async {
    try {
      final result = await _searchDataSource.searchMovies(query, page: page);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<SearchEntity>> _searchViaExtractor(
    ProviderEntity providerInfo,
    String query,
    int page,
  ) async {
    try {
      await _ensureExtractorReady(providerInfo);

      final json = await _extractor.call(
        providerInfo.extractor!.name,
        'search',
        {'query': query, 'page': page},
      );
      final result = SearchModel.fromJson(json);
      return Success(result);
    } catch (e) {
      debugPrint('[ProviderManager] extractor search error: $e');
      return Failure(Exception('Extractor xatolik: ${e.toString()}'));
    }
  }

  void dispose() {
    _extractor.dispose();
  }
}
