import 'package:easy_localization/easy_localization.dart';

import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

/// Reminders for episodes about to air.
///
/// Local, not push. The phone already knows when every episode on your list
/// airs — the calendar fetched it — so routing that through a server, a token
/// and a delivery receipt would add three ways to fail to something that can
/// simply be scheduled. It also works with no signal.
///
/// Rescheduled wholesale rather than diffed: the schedule shifts constantly as
/// episodes are delayed and announced, and cancelling a window's worth before
/// laying it down again is both simpler and correct, where a diff has to be
/// right about what changed.
class AiringReminders {
  AiringReminders({
    required NotificationService notifications,
    required HiveService hive,
  }) : _notifications = notifications,
       _hive = hive;

  final NotificationService _notifications;
  final HiveService _hive;

  /// How long before the episode the reminder fires.
  static const Duration lead = Duration(minutes: 10);

  /// Only the next few days are scheduled. The platform caps how many pending
  /// notifications an app may hold, and a reminder three weeks out is one the
  /// schedule will have changed under anyway.
  static const Duration horizon = Duration(days: 7);

  /// Ids live in their own block so cancelling ours never touches a
  /// notification some other part of the app scheduled.
  static const int _idBase = 900000;
  static const int _idSpan = 1000;

  bool get enabled => _hive.airingRemindersEnabled;

  Future<void> setEnabled(bool value) async {
    await _hive.setAiringRemindersEnabled(value);
    if (!value) await _cancelAll();
  }

  /// Lays down the next window of reminders for [entries].
  ///
  /// Silent on failure: this runs behind a screen the user is looking at, and a
  /// scheduling problem is not worth interrupting them for.
  Future<void> sync(Iterable<AnilistListEntry> entries) async {
    try {
      await _cancelAll();
      if (!enabled) return;

      final now = DateTime.now();
      final until = now.add(horizon);
      final due = <({DateTime at, String title, int episode})>[];

      for (final entry in entries) {
        final airing = entry.media.nextAiring;
        if (airing == null) continue;
        final at = airing.airsAt.subtract(lead);
        // Already gone, or too far out to be worth a slot.
        if (!at.isAfter(now) || airing.airsAt.isAfter(until)) continue;
        due.add((
          at: at,
          title: entry.media.englishTitle ??
              entry.media.romajiTitle ??
              entry.media.nativeTitle ??
              '',
          episode: airing.episode,
        ));
      }

      due.sort((a, b) => a.at.compareTo(b.at));

      var scheduled = 0;
      for (var i = 0; i < due.length && scheduled < _idSpan; i++) {
        final item = due[i];
        if (item.title.isEmpty) continue;
        await _notifications.scheduleAt(
          id: _idBase + scheduled,
          when: item.at,
          title: item.title,
          body: 'anilist.reminder_body'.tr(
            namedArgs: {'episode': '${item.episode}'},
          ),
        );
        scheduled++;
      }
      await _hive.setAiringReminderCount(scheduled);
    } catch (_) {
      // Scheduling is best effort; the calendar itself still works.
    }
  }

  /// Cancels exactly what was laid down last time.
  ///
  /// The count is remembered rather than sweeping the whole id block: walking a
  /// thousand ids costs a platform call each, and cancelAll() would take out
  /// notifications this class never scheduled.
  Future<void> _cancelAll() async {
    final count = _hive.airingReminderCount;
    if (count <= 0) return;
    await _notifications.cancelAllScheduled(
      [for (var i = 0; i < count; i++) _idBase + i],
    );
    await _hive.setAiringReminderCount(0);
  }
}
