import 'dart:async';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';

/// Fans a query out across a set of providers with **bounded concurrency**, a
/// **per-provider timeout**, and **incremental** emission — the core reason the
/// feature never freezes even with a large provider set:
///
/// - never runs more than [concurrency] provider searches at once;
/// - a slow/hung provider is dropped at [perProviderTimeout] (its native call
///   keeps running in the background but its result is ignored);
/// - each provider's result is emitted the moment it resolves;
/// - cancelling the returned stream stops scheduling further work;
/// - one provider throwing never fails the batch.
///
/// Native `cs:`/`an:`/`mn:` searches already run off the platform thread, so the
/// pool only guards against overwhelming the device — the UI thread never blocks.
class CrossSearchEngine {
  CrossSearchEngine({required this.jsRuntime, required this.dataSource});

  final JsRuntimeService jsRuntime;
  final SearchDataSource dataSource;

  static const int defaultConcurrency = 5;
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// A synthetic id used for the single collapsed backend ("Sozo") search leg.
  static const String serverId = '__server__';

  Stream<ProviderSearchResult> search({
    required List<ProviderRef> set,
    required String query,
    int concurrency = defaultConcurrency,
    Duration perProviderTimeout = defaultTimeout,
  }) {
    // Collapse every server provider into a single backend call — the backend
    // search endpoint is provider-agnostic, so N server providers = 1 leg.
    final tasks = <ProviderRef>[];
    var hasServer = false;
    for (final p in set) {
      if (p.kind == ProviderKind.server) {
        hasServer = true;
      } else {
        tasks.add(p);
      }
    }
    if (hasServer) {
      tasks.add(const ProviderRef(
        id: serverId,
        name: 'Sozo',
        kind: ProviderKind.server,
      ));
    }

    final controller = StreamController<ProviderSearchResult>();
    var cancelled = false;
    controller.onCancel = () => cancelled = true;

    Future<void> drain() async {
      var next = 0;
      final pool = concurrency < 1 ? 1 : concurrency;
      Future<void> worker() async {
        while (!cancelled) {
          final i = next++;
          if (i >= tasks.length) return;
          final result = await _searchOne(tasks[i], query, perProviderTimeout);
          if (cancelled || controller.isClosed) return;
          controller.add(result);
        }
      }

      await Future.wait([for (var w = 0; w < pool; w++) worker()]);
      if (!controller.isClosed) await controller.close();
    }

    // Fire-and-forget; every error is captured inside [_searchOne].
    unawaited(drain());
    return controller.stream;
  }

  Future<ProviderSearchResult> _searchOne(
    ProviderRef ref,
    String query,
    Duration timeout,
  ) async {
    try {
      final items = await _dispatch(ref, query).timeout(timeout);
      return ProviderSearchResult(
        provider: ref,
        items: items,
        status:
            items.isEmpty ? ProviderSearchStatus.empty : ProviderSearchStatus.ok,
      );
    } on TimeoutException {
      return ProviderSearchResult(
        provider: ref,
        items: const [],
        status: ProviderSearchStatus.timeout,
      );
    } catch (_) {
      return ProviderSearchResult(
        provider: ref,
        items: const [],
        status: ProviderSearchStatus.error,
      );
    }
  }

  Future<List<MovieEntity>> _dispatch(ProviderRef ref, String query) async {
    final id = ref.id;
    if (id.startsWith('cs:')) {
      final map = await CloudStreamChannel.search(id.substring(3), query);
      return map.isEmpty ? const [] : SearchModel.fromJson(map).items;
    }
    if (id.startsWith('an:')) {
      final map = await AniyomiChannel.search(id.substring(3), query);
      return map.isEmpty ? const [] : SearchModel.fromJson(map).items;
    }
    if (id.startsWith('mn:')) {
      final map = await MangaChannel.search(id.substring(3), query);
      return map.isEmpty ? const [] : SearchModel.fromJson(map).items;
    }
    if (ref.kind == ProviderKind.js) {
      final map = await jsRuntime.trySearch(id, query, 1);
      return map == null ? const [] : SearchModel.fromJson(map).items;
    }
    // server — provider-agnostic backend search.
    final model = await dataSource.searchMovies(query);
    return model.items;
  }
}
