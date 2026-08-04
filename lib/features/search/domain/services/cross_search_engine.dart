import 'dart:async';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
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
  CrossSearchEngine({
    required this.jsRuntime,
    required this.dataSource,
    required this.mangayomi,
  });

  final JsRuntimeService jsRuntime;
  final SearchDataSource dataSource;
  final MangayomiBridge mangayomi;

  static const int defaultConcurrency = 5;
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Budget for an on-device extension host (`cs:` / `an:` / `mn:`).
  ///
  /// The first search against a freshly-installed source has to download and
  /// dex-load its extension APK before it can issue a single request — several
  /// megabytes over whatever connection the user has. Under the 10s budget that
  /// suits an HTTP provider, every extension source timed out on first use and
  /// the feature looked broken precisely when the user had just added sources.
  /// Later searches hit the cached APK and return in well under a second, so
  /// this ceiling is only ever paid once per source.
  static const Duration channelTimeout = Duration(seconds: 45);

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
    // Extension hosts get the longer budget — see [channelTimeout].
    final effective =
        ref.kind == ProviderKind.channel && timeout < channelTimeout
            ? channelTimeout
            : timeout;
    try {
      final items = await _dispatch(ref, query).timeout(effective);
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

  /// Unwraps an extension host's response.
  ///
  /// Throws when the source is genuinely broken (empty map = channel failure,
  /// or an `error` field from the host) so the leg is reported as `error`
  /// rather than `empty` — "this source is down" and "no match here" look
  /// identical to the user otherwise, and only one of them is worth retrying.
  List<MovieEntity> _unwrap(Map<String, dynamic> map, String label) {
    if (map.isEmpty) throw Exception('$label: source unavailable');
    final model = SearchModel.fromJson(map);
    final error = (map['error'] as String?)?.trim();
    if (model.items.isEmpty && error != null && error.isNotEmpty) {
      throw Exception('$label: $error');
    }
    return model.items;
  }

  Future<List<MovieEntity>> _dispatch(ProviderRef ref, String query) async {
    final id = ref.id;
    if (id.startsWith('cs:')) {
      return _unwrap(
          await CloudStreamChannel.search(id.substring(3), query), ref.name);
    }
    if (id.startsWith('an:')) {
      return _unwrap(
          await AniyomiChannel.search(id.substring(3), query), ref.name);
    }
    if (id.startsWith('mn:')) {
      return _unwrap(
          await MangaChannel.search(id.substring(3), query), ref.name);
    }
    if (id.startsWith('my:')) {
      return _unwrap(
          await mangayomi.search(id.substring(3), query), ref.name);
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
