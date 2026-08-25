import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import 'package:soplay/features/torrent/data/indexers/nekobt_indexer.dart';
import 'package:soplay/features/torrent/data/indexers/nyaa_indexer.dart';
import 'package:soplay/features/torrent/data/indexers/tokyotosho_indexer.dart';
import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/domain/entities/release_info.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// Quality filters applied to results after they come back.
///
/// None of these can be pushed down to the trackers: no anime indexer lets you
/// query by resolution, codec or subtitle style, because none of them store
/// those as fields — the information only exists inside the release name. So
/// the tracker narrows by category and text, and this narrows the rest.
class TorrentFilters {
  const TorrentFilters({
    this.minSeeders = 1,
    this.minResolution,
    this.maxResolution,
    this.excludeHardsubs = false,
    this.excludeMiniEncodes = true,
    this.trustedOnly = false,
    this.excludeRemakes = false,
    this.requireDualAudio = false,
    this.excludeBatches = false,
    this.groups = const {},
  });

  /// Defaults to 1: a torrent with no seeders cannot be streamed at all, and
  /// showing it is offering the user a button that is guaranteed to fail.
  /// Results with an *unknown* seeder count are never filtered by this.
  final int minSeeders;

  final int? minResolution;
  final int? maxResolution;

  /// Drop releases whose subtitles are burned into the video.
  final bool excludeHardsubs;

  /// On by default. The wiki describes mini-encode quality loss as "severe",
  /// and they are indistinguishable from a good encode by name alone until you
  /// are already watching one.
  final bool excludeMiniEncodes;

  /// Only uploads from tracker-vouched accounts.
  final bool trustedOnly;

  final bool excludeRemakes;
  final bool requireDualAudio;

  /// Drop season packs and episode ranges. Useful when the user is looking for
  /// one episode and does not want to pick a file out of a 24-episode torrent.
  final bool excludeBatches;

  /// Release groups to keep, lowercased. Empty means every group.
  final Set<String> groups;

  bool allows(TorrentResult result) {
    final seeders = result.seeders;
    if (seeders != null && seeders < minSeeders) return false;
    if (trustedOnly && !result.trusted) return false;
    if (excludeRemakes && result.remake) return false;

    final release = result.release;
    final height = release.resolutionHeight;
    // An unparseable resolution is not evidence of a bad one — releases with
    // no resolution in the name survive the filter rather than vanishing.
    if (height != null) {
      if (minResolution != null && height < minResolution!) return false;
      if (maxResolution != null && height > maxResolution!) return false;
    }
    if (excludeHardsubs && release.hasHardsubs) return false;
    if (excludeMiniEncodes && release.source == ReleaseSource.miniEncode) {
      return false;
    }
    if (requireDualAudio && !release.dualAudio) return false;
    if (excludeBatches && release.batch) return false;
    if (groups.isNotEmpty) {
      final group = release.group?.toLowerCase();
      if (group == null || !groups.contains(group)) return false;
    }
    return true;
  }
}

/// Searches every enabled tracker at once and returns one merged list.
///
/// Three things make this more than a `Future.wait`:
///
/// 1. **Isolation.** One tracker being down, rate-limited or redesigned must
///    not empty the results. Indexers already swallow their own errors; this
///    also caps each one with its own timeout so a hanging socket cannot hold
///    the whole search open.
/// 2. **Deduplication.** Tokyo Toshokan mirrors Nyaa and nekoBT overlaps both,
///    so the same release routinely arrives three times under three different
///    info-hash encodings. Merging them is what keeps the list readable.
/// 3. **Ranking.** Trackers sort within themselves; nothing sorts across them.
class TorrentSearchRepository {
  TorrentSearchRepository({Dio? dio}) : _dio = dio ?? _buildDio() {
    _indexers = [
      NyaaIndexer(_dio),
      TokyoToshokanIndexer(_dio),
      NekoBtIndexer(_dio),
      NyaaIndexer(_dio, sukebei: true),
    ];
  }

  final Dio _dio;
  late final List<TorrentIndexer> _indexers;

  /// A client of its own, deliberately not the app's injected [Dio].
  ///
  /// The shared instance carries a base URL and auth interceptors for Sozo's
  /// own backend. Reusing it here would attach the user's bearer token to
  /// requests going to nyaa.si and nekobt.to — sending an account credential
  /// to a third-party tracker, which is exactly the kind of leak the rest of
  /// this feature exists to avoid.
  static Dio _buildDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: true,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          'Accept': 'application/rss+xml, application/xml, text/html;q=0.9, */*;q=0.8',
        },
        // Trackers answer rate limits and maintenance with 4xx/5xx bodies we
        // want to inspect rather than throw on.
        validateStatus: (status) => status != null && status < 500,
      ));

  /// Every indexer Sozo knows about, for the tracker-toggle settings screen.
  List<TorrentIndexer> get indexers => List.unmodifiable(_indexers);

  /// Hard ceiling per tracker. Past this the result is not worth waiting for —
  /// the other trackers have already answered and the user is watching a
  /// spinner.
  static const _perIndexerTimeout = Duration(seconds: 15);

  /// Runs [query] against every enabled tracker and returns the merged,
  /// filtered, ranked list.
  ///
  /// [enabledIds] is the user's tracker selection; null means all non-NSFW
  /// trackers. [nsfwAllowed] gates Sukebei the same way the rest of the app
  /// gates adult sources.
  Future<List<TorrentResult>> search(
    TorrentQuery query, {
    TorrentFilters filters = const TorrentFilters(),
    Set<String>? enabledIds,
    bool nsfwAllowed = false,
    CancelToken? cancelToken,
  }) async {
    if (query.term.trim().isEmpty) return const [];

    final selected = _indexers.where((indexer) {
      if (indexer.isNsfw && !nsfwAllowed) return false;
      if (enabledIds != null && !enabledIds.contains(indexer.id)) return false;
      // Asking a tracker for a category it does not model returns results for
      // the wrong thing, which is worse than returning none.
      if (!indexer.categories.contains(query.category)) return false;
      if (query.page > 1 && !indexer.supportsPagination) return false;
      return true;
    }).toList();

    if (selected.isEmpty) return const [];

    final batches = await Future.wait(
      selected.map(
        (indexer) => indexer
            .search(query, cancelToken: cancelToken)
            .timeout(_perIndexerTimeout, onTimeout: () => const [])
            .catchError((Object error, StackTrace _) {
          // Indexers are not supposed to throw, but a bug in one of them must
          // still not take down the search.
          developer.log('${indexer.id} failed: $error', name: 'torrent');
          return const <TorrentResult>[];
        }),
      ),
    );

    final merged = _dedupe(batches.expand((batch) => batch));
    final kept = merged.where(filters.allows).toList();
    _rank(kept, query.sort);
    return kept;
  }

  /// Collapses the same release arriving from several trackers into one row.
  ///
  /// Keyed on the normalised info hash, which is the only identifier that is
  /// genuinely the same across trackers — titles differ in whitespace and
  /// bracket style even when the torrent is byte-identical. Rows with no info
  /// hash at all (a `.torrent` URL and nothing else) fall back to a
  /// title-based key so they are still deduplicated against each other.
  List<TorrentResult> _dedupe(Iterable<TorrentResult> all) {
    final byKey = <String, TorrentResult>{};
    for (final result in all) {
      final key = result.infoHash ??
          'title:${result.title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';
      final existing = byKey[key];
      byKey[key] = existing == null ? result : _merge(existing, result);
    }
    return byKey.values.toList();
  }

  /// Combines two views of one torrent, preferring whichever actually knows
  /// something.
  ///
  /// The common case is Nyaa (real seeder counts, a trusted flag, no magnet)
  /// against Tokyo Toshokan (a ready-made magnet, no swarm data). Taking the
  /// union rather than picking a winner is what makes the merged row better
  /// than either source alone.
  TorrentResult _merge(TorrentResult a, TorrentResult b) {
    // Prefer the row whose tracker reports swarm health, since that is what
    // ranking and the dead-torrent warning both key off.
    final primary = a.seeders != null ? a : (b.seeders != null ? b : a);
    final other = identical(primary, a) ? b : a;

    return TorrentResult(
      title: primary.title,
      indexerId: primary.indexerId,
      indexerName: primary.indexerName,
      release: primary.release,
      infoHash: primary.infoHash ?? other.infoHash,
      magnetUrl: primary.magnetUrl ?? other.magnetUrl,
      torrentFileUrl: primary.torrentFileUrl ?? other.torrentFileUrl,
      pageUrl: primary.pageUrl ?? other.pageUrl,
      seeders: primary.seeders ?? other.seeders,
      leechers: primary.leechers ?? other.leechers,
      completed: primary.completed ?? other.completed,
      sizeBytes: primary.sizeBytes ?? other.sizeBytes,
      sizeLabel: primary.sizeLabel ?? other.sizeLabel,
      publishedAt: primary.publishedAt ?? other.publishedAt,
      categoryId: primary.categoryId ?? other.categoryId,
      categoryLabel: primary.categoryLabel ?? other.categoryLabel,
      // Vouched on any tracker is still vouched.
      trusted: primary.trusted || other.trusted,
      // Flagged as a re-upload anywhere is worth surfacing.
      remake: primary.remake || other.remake,
    );
  }

  void _rank(List<TorrentResult> results, TorrentSort sort) {
    switch (sort) {
      case TorrentSort.seeders:
        results.sort((a, b) => _seedScore(b).compareTo(_seedScore(a)));
      case TorrentSort.size:
        results.sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
      case TorrentSort.downloads:
        results.sort((a, b) => (b.completed ?? 0).compareTo(a.completed ?? 0));
      case TorrentSort.date:
        results.sort((a, b) {
          final aDate = a.publishedAt;
          final bDate = b.publishedAt;
          if (aDate == null && bDate == null) return 0;
          // Undated rows sink; they are almost always the scraped trackers,
          // and a date-sorted list they float to the top of is just wrong.
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });
    }
  }

  /// Sorts by seeders while keeping unknown-swarm rows in the middle of the
  /// list rather than at either extreme — they are neither known-good nor
  /// known-dead, and burying them would hide everything Tokyo Toshokan found.
  int _seedScore(TorrentResult result) => result.seeders ?? 5;

  void dispose() => _dio.close(force: true);
}
