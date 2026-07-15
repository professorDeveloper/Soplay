import 'dart:async';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

/// Follow serials and detect new episodes. The update check reuses the same
/// freeze-proof pattern as cross-search: bounded concurrency + per-title
/// timeout, so it never hangs no matter how many titles are followed.
class FollowService {
  FollowService({
    required this.hive,
    required this.getEpisodes,
    required this.notifications,
  });

  final HiveService hive;
  final GetEpisodesUseCase getEpisodes;
  final NotificationService notifications;

  List<FollowedTitle> list() =>
      hive.getFollowedRaw().map(FollowedTitle.fromJson).toList();

  bool isFollowed(String contentUrl) =>
      hive.getFollowedRaw().any((e) => e['contentUrl'] == contentUrl);

  Future<void> follow(FollowedTitle title) async {
    final items = hive.getFollowedRaw();
    if (items.any((e) => e['contentUrl'] == title.contentUrl)) return;
    items.insert(0, title.toJson());
    await hive.setFollowedRaw(items);
  }

  Future<void> unfollow(String contentUrl) async {
    final items = hive.getFollowedRaw()
      ..removeWhere((e) => e['contentUrl'] == contentUrl);
    await hive.setFollowedRaw(items);
  }

  /// Re-check every followed serial for new episodes. Returns how many grew.
  /// Fires one local notification per grown title (when [notify] is true).
  ///
  /// Freeze-proof: at most [concurrency] checks run at once, each capped at
  /// [timeout]; counts are persisted in a single write at the end (no races).
  Future<int> checkForUpdates({
    int concurrency = 3,
    Duration timeout = const Duration(seconds: 12),
    bool notify = true,
  }) async {
    final items = list();
    if (items.isEmpty) return 0;

    final newCounts = <String, int>{};
    var index = 0;
    var grown = 0;

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= items.length) return;
        final t = items[i];
        try {
          final res = await getEpisodes(t.contentUrl, provider: t.provider)
              .timeout(timeout);
          if (!res.isSuccess) continue;
          final pb = res.getOrNull();
          if (pb == null) continue;
          final count = pb.total > 0 ? pb.total : pb.episodes.length;
          if (count <= 0) continue;
          newCounts[t.contentUrl] = count;
          if (t.lastEpisodeCount > 0 && count > t.lastEpisodeCount) {
            final delta = count - t.lastEpisodeCount;
            grown++;
            if (notify) {
              await notifications.showLocalNotification(
                id: t.contentUrl.hashCode & 0x7fffffff,
                title: 'New episode',
                body:
                    '${t.title} · $delta new episode${delta > 1 ? 's' : ''}',
                data: {'url': t.contentUrl, 'provider': t.provider},
              );
            }
          }
        } catch (_) {
          // timeout / network / provider error — skip this title, keep going.
        }
      }
    }

    await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);

    // Single merged write — re-read in case the follow list changed mid-check.
    if (newCounts.isNotEmpty) {
      final raw = hive.getFollowedRaw();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in raw) {
        final url = e['contentUrl'];
        if (url is String && newCounts.containsKey(url)) {
          e['lastEpisodeCount'] = newCounts[url];
          e['lastCheckedAt'] = now;
        }
      }
      await hive.setFollowedRaw(raw);
    }
    return grown;
  }
}
