import 'package:flutter/foundation.dart';

import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// The airing week, one day at a time.
///
/// Days are fetched on demand and kept, rather than pulling the whole week up
/// front: a week of global airings is several hundred entries and six of those
/// days are ones the user never looks at. Switching back to a day already seen
/// is then instant.
class AiringCalendarController extends ChangeNotifier {
  AiringCalendarController({required AnilistService service})
    : _service = service;

  final AnilistService _service;

  /// Cache and in-flight state are keyed by the day's midnight, so a rebuild
  /// with a fresh DateTime.now() still hits the same entry.
  final Map<DateTime, List<AnilistScheduledAiring>> _byDay = {};
  final Map<DateTime, String> _errors = {};
  final Set<DateTime> _loading = <DateTime>{};

  /// Media ids on the viewer's own list, used to mark and to filter.
  Set<int> _mine = <int>{};

  bool _mineOnly = false;
  late DateTime _selected = startOfDay(DateTime.now());

  DateTime get selected => _selected;
  bool get mineOnly => _mineOnly;
  bool get isConnected => _service.isConnected;

  bool get loading => _loading.contains(_selected);
  String? get error => _errors[_selected];

  /// The seven days on offer, from today.
  ///
  /// Anchored to today rather than to the calendar week: "what's on this week"
  /// is only useful looking forward, and a Sunday would otherwise offer six
  /// days that have already happened.
  List<DateTime> get week {
    final today = startOfDay(DateTime.now());
    return List<DateTime>.generate(7, (i) => today.add(Duration(days: i)));
  }

  /// The selected day's airings, newest filter applied.
  List<AnilistScheduledAiring> get visible {
    final all = _byDay[_selected] ?? const <AnilistScheduledAiring>[];
    if (!_mineOnly) return all;
    return all.where((a) => _mine.contains(a.media.id)).toList(growable: false);
  }

  /// Whether the day holds anything at all, regardless of the filter — so the
  /// empty state can say "nothing on your list today" instead of "nothing at
  /// all today", which would be wrong.
  bool get dayHasAny => (_byDay[_selected] ?? const []).isNotEmpty;

  bool isMine(int mediaId) => _mine.contains(mediaId);

  int countFor(DateTime day) => (_byDay[startOfDay(day)] ?? const []).length;

  void select(DateTime day) {
    final normalised = startOfDay(day);
    if (normalised == _selected) return;
    _selected = normalised;
    notifyListeners();
    load();
  }

  void setMineOnly(bool value) {
    if (_mineOnly == value) return;
    _mineOnly = value;
    notifyListeners();
  }

  /// Records which media the viewer follows.
  ///
  /// Passed in rather than fetched here: the library screens already hold this
  /// list, and a second copy would drift from theirs after an edit.
  void setLibrary(Iterable<AnilistListEntry> entries) {
    final ids = entries.map((e) => e.media.id).toSet();
    if (setEquals(ids, _mine)) return;
    _mine = ids;
    notifyListeners();
  }

  Future<void> load({bool force = false}) async {
    final day = _selected;
    if (_loading.contains(day)) return;
    if (!force && _byDay.containsKey(day)) return;

    _loading.add(day);
    _errors.remove(day);
    notifyListeners();
    try {
      final schedule = await _service.api.airingSchedule(
        from: day,
        to: day.add(const Duration(days: 1)),
      );
      _byDay[day] = schedule;
    } catch (e) {
      _errors[day] = e is AnilistException
          ? e.message
          : 'Could not load the airing schedule';
    } finally {
      _loading.remove(day);
      // The day may no longer be selected — the user can switch while a fetch
      // is in flight — but the result is cached either way, so notifying is
      // still correct: it repaints whichever day they landed on.
      notifyListeners();
    }
  }

  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
