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

typedef _Leg = ({List<MovieEntity> items, int page, int totalPages});

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

  /// Every selected provider is its own leg, server providers included: the
  /// backend takes an explicit `provider`, so collapsing them into one call was
  /// both a lie in the summary ("1 of 1 sources") and a silent no-op for every
  /// server provider the user picked beyond the first.
  Stream<ProviderSearchResult> search({
    required List<ProviderRef> set,
    required String query,
    int page = 1,
    int concurrency = defaultConcurrency,
    Duration perProviderTimeout = defaultTimeout,
  }) {
    final tasks = List<ProviderRef>.of(set);
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
          final result = await searchProvider(
            tasks[i],
            query,
            page: page,
            timeout: perProviderTimeout,
          );
          if (cancelled || controller.isClosed) return;
          controller.add(result);
        }
      }

      await Future.wait([for (var w = 0; w < pool; w++) worker()]);
      if (!controller.isClosed) await controller.close();
    }

    // Fire-and-forget; every error is captured inside [searchProvider].
    unawaited(drain());
    return controller.stream;
  }

  /// One leg on its own — used to retry a single failed source and to page it.
  Future<ProviderSearchResult> searchProvider(
    ProviderRef ref,
    String query, {
    int page = 1,
    Duration timeout = defaultTimeout,
  }) async {
    // Extension hosts get the longer budget — see [channelTimeout].
    final effective =
        ref.kind == ProviderKind.channel && timeout < channelTimeout
            ? channelTimeout
            : timeout;
    try {
      final leg = await _dispatch(ref, query, page).timeout(effective);
      return ProviderSearchResult(
        provider: ref,
        items: leg.items,
        page: leg.page,
        totalPages: leg.totalPages,
        status: leg.items.isEmpty
            ? ProviderSearchStatus.empty
            : ProviderSearchStatus.ok,
      );
    } on TimeoutException {
      return ProviderSearchResult(
        provider: ref,
        items: const [],
        status: ProviderSearchStatus.timeout,
      );
    } catch (e) {
      return ProviderSearchResult(
        provider: ref,
        items: const [],
        status: ProviderSearchStatus.error,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Unwraps an extension host's response.
  ///
  /// Throws when the source is genuinely broken (empty map = channel failure,
  /// or an `error` field from the host) so the leg is reported as `error`
  /// rather than `empty` — "this source is down" and "no match here" look
  /// identical to the user otherwise, and only one of them is worth retrying.
  _Leg _unwrap(Map<String, dynamic> map, String label) {
    if (map.isEmpty) throw Exception('$label: source unavailable');
    final model = SearchModel.fromJson(map);
    final error = (map['error'] as String?)?.trim();
    if (model.items.isEmpty && error != null && error.isNotEmpty) {
      throw Exception('$label: $error');
    }
    return (items: model.items, page: model.page, totalPages: model.totalPages);
  }

  Future<_Leg> _dispatch(ProviderRef ref, String query, int page) async {
    final id = ref.id;
    if (id.startsWith('cs:')) {
      return _unwrap(
        await CloudStreamChannel.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    if (id.startsWith('an:')) {
      return _unwrap(
        await AniyomiChannel.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    if (id.startsWith('mn:')) {
      return _unwrap(
        await MangaChannel.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    if (id.startsWith('my:')) {
      return _unwrap(
        await mangayomi.search(id.substring(3), query, page: page),
        ref.name,
      );
    }
    if (ref.kind == ProviderKind.js) {
      final map = await jsRuntime.trySearch(id, query, page);
      // A null response means the extractor is missing or failed to load. That
      // is a broken source, not "no match here" — reporting it as empty is the
      // one place this engine used to invert its own distinction.
      if (map == null) throw Exception('${ref.name}: source unavailable');
      return _unwrap(map, ref.name);
    }
    final model = await dataSource.searchMovies(
      query,
      page: page,
      provider: ref.id,
    );
    return (items: model.items, page: model.page, totalPages: model.totalPages);
  }
}
