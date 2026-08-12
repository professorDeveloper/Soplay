import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riasdxd/core/constants/app_constants.dart';
import 'package:riasdxd/features/home/data/datasources/home_data_source.dart';
import 'package:riasdxd/features/home/domain/entities/home_section_entity.dart';
import 'package:riasdxd/features/home/domain/entities/movie.dart';
import 'package:riasdxd/features/notifications/data/services/notification_service.dart';

/// Client-side watcher that surfaces LOCAL notifications for newly-appeared
/// "recent releases" and "top trending" titles.
///
/// Deliberately self-contained — the backend never has to push anything. On a
/// throttled schedule we pull the current provider's `/contents/home`, pick out
/// the recent-releases and trending sections (matched by section key/label),
/// diff their items against the last-seen set we persisted, and fire one grouped
/// local notification per category when something new shows up.
///
/// Freeze-proof and side-effect-light, mirroring [FollowService.checkForUpdates]
/// and `UpdateChecker`: a single timed network call, a bounded body, and one
/// Hive write per category. The FIRST run only seeds the baseline (never
/// notifies), so a fresh install is not blasted with everything already on the
/// home feed.
class ReleaseNotifier {
  ReleaseNotifier({
    required this.homeData,
    required this.notifications,
  });

  final HomeDataSource homeData;
  final NotificationService notifications;

  // ── Persistence keys (settings box) ──────────────────────────────────────
  static const _recentEnabledKey = 'notif_recent_releases_enabled';
  static const _trendingEnabledKey = 'notif_top_trending_enabled';
  static const _recentSeenKey = 'notif_recent_releases_seen';
  static const _trendingSeenKey = 'notif_top_trending_seen';
  static const _lastPollKey = 'notif_releases_last_poll';

  static const _pollInterval = Duration(hours: 3);
  // Cap the persisted seen-set so it can't grow without bound.
  static const _maxSeen = 300;
  // Keywords that identify each section by its key or label (case-insensitive).
  static const _recentKeywords = ['recent', 'new', 'release', 'latest'];
  static const _trendingKeywords = ['trend', 'popular', 'top', 'hot'];

  // Fixed IDs so a fresh alert of the same kind replaces the previous one
  // instead of stacking.
  static const _recentNotifId = 990001;
  static const _trendingNotifId = 990002;

  bool _running = false;

  Box get _box => Hive.box(AppConstants.settingsBox);

  // ── Preferences ──────────────────────────────────────────────────────────
  bool get recentReleasesEnabled =>
      _box.get(_recentEnabledKey, defaultValue: true) as bool;
  Future<void> setRecentReleasesEnabled(bool value) =>
      _box.put(_recentEnabledKey, value);

  bool get topTrendingEnabled =>
      _box.get(_trendingEnabledKey, defaultValue: true) as bool;
  Future<void> setTopTrendingEnabled(bool value) =>
      _box.put(_trendingEnabledKey, value);

  bool get _anyEnabled => recentReleasesEnabled || topTrendingEnabled;

  /// Throttled poll. Safe to call on every app start / resume — it no-ops when
  /// called again within [_pollInterval], when both categories are disabled, or
  /// when a poll is already in flight. Never throws.
  Future<void> run({bool force = false}) async {
    if (_running) return;
    if (!_anyEnabled) return;
    if (!force && _isThrottled()) return;
    _running = true;
    try {
      final data =
          await homeData.loadHome().timeout(const Duration(seconds: 15));
      await _box.put(_lastPollKey, DateTime.now().millisecondsSinceEpoch);
      final sections = data.sections;
      if (recentReleasesEnabled) {
        await _process(
          section: _match(sections, _recentKeywords),
          seenKey: _recentSeenKey,
          notifId: _recentNotifId,
          type: 'new_release',
          singularTitle: 'New release',
          pluralTitle: (n) => '$n new releases',
        );
      }
      if (topTrendingEnabled) {
        await _process(
          section: _match(sections, _trendingKeywords),
          seenKey: _trendingSeenKey,
          notifId: _trendingNotifId,
          type: 'top_trending',
          singularTitle: 'Now trending',
          pluralTitle: (n) => '$n titles trending',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ReleaseNotifier] $e');
    } finally {
      _running = false;
    }
  }

  bool _isThrottled() {
    final ts = _box.get(_lastPollKey);
    if (ts is! int) return false;
    return DateTime.now().millisecondsSinceEpoch - ts <
        _pollInterval.inMilliseconds;
  }

  /// First section whose key or label contains any of [keywords].
  HomeSectionEntity? _match(
    List<HomeSectionEntity> sections,
    List<String> keywords,
  ) {
    for (final s in sections) {
      final key = s.key.toLowerCase();
      final label = s.label.toLowerCase();
      if (keywords.any((k) => key.contains(k) || label.contains(k))) {
        return s;
      }
    }
    return null;
  }

  String _idOf(MovieEntity m) {
    if (m.externalId.isNotEmpty) return m.externalId;
    if (m.url.isNotEmpty) return m.url;
    return m.slug;
  }

  Future<void> _process({
    required HomeSectionEntity? section,
    required String seenKey,
    required int notifId,
    required String type,
    required String singularTitle,
    required String Function(int) pluralTitle,
  }) async {
    if (section == null || section.items.isEmpty) return;

    final items = section.items;
    final currentIds =
        items.map(_idOf).where((id) => id.isNotEmpty).toList();

    final rawSeen = _box.get(seenKey);
    final seededBefore = rawSeen is List;
    final seen = seededBefore ? rawSeen.map((e) => '$e').toSet() : <String>{};

    // First run for this category: seed the baseline silently so we don't
    // announce titles that were already on the feed before the feature existed.
    if (!seededBefore) {
      await _box.put(seenKey, _capped(currentIds));
      return;
    }

    final fresh = <MovieEntity>[
      for (final m in items)
        if (_idOf(m).isNotEmpty && !seen.contains(_idOf(m))) m,
    ];

    // Persist the merged, capped seen-set regardless of whether we notify, so a
    // title is only ever announced once. Current ids go first (newest-first).
    await _box.put(seenKey, _capped([...currentIds, ...seen]));

    if (fresh.isEmpty) return;

    final String title;
    final String body;
    final payload = <String, dynamic>{'type': type};
    if (fresh.length == 1) {
      title = singularTitle;
      body = fresh.first.title;
      if (fresh.first.url.isNotEmpty) {
        payload['contentUrl'] = fresh.first.url;
        payload['provider'] = fresh.first.provider;
      }
    } else {
      title = pluralTitle(fresh.length);
      final names = fresh.take(3).map((m) => m.title).join(', ');
      body = fresh.length > 3 ? '$names…' : names;
    }

    await notifications.showLocalNotification(
      id: notifId,
      title: title,
      body: body,
      data: payload,
    );
  }

  /// De-dup preserving order (front = newest), capped at [_maxSeen].
  List<String> _capped(List<String> ids) {
    final seen = <String>{};
    final out = <String>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(id);
      if (out.length >= _maxSeen) break;
    }
    return out;
  }
}
