import 'package:flutter/foundation.dart';

import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// Loads and mutates the viewer's AniList library.
///
/// Holds the entries in memory for the life of the screen so switching status
/// tabs is instant — AniList returns every status in a single request, and
/// re-fetching per tab would spend a round trip to show data already held.
class AnilistLibraryController extends ChangeNotifier {
  AnilistLibraryController({required AnilistService service}) : _service = service;

  final AnilistService _service;

  List<AnilistListEntry> _entries = const [];
  bool _loading = false;
  String? _error;

  /// Entry ids with a write in flight, so a card can show a spinner without
  /// blocking the rest of the list.
  final Set<int> _busy = <int>{};

  List<AnilistListEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;
  bool isBusy(int entryId) => _busy.contains(entryId);
  bool get isConnected => _service.isConnected;
  AnilistViewer? get viewer => _service.viewer;

  /// Entries of one status, most recently updated first — which is the order
  /// that puts what the viewer is actually watching at the top.
  List<AnilistListEntry> byStatus(AnilistStatus status) {
    final out = _entries.where((e) => e.status == status.value).toList();
    out.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
    return out;
  }

  /// The viewer's entry for one title, or null when it is not on their list.
  ///
  /// Keyed by media rather than entry id because the airing calendar only ever
  /// holds a media — it starts from the schedule, not from the library.
  AnilistListEntry? entryForMedia(int mediaId) {
    for (final e in _entries) {
      if (e.media.id == mediaId) return e;
    }
    return null;
  }

  int countOf(AnilistStatus status) =>
      _entries.where((e) => e.status == status.value).length;

  /// Everything with an announced next episode, soonest first.
  ///
  /// Drawn from the library rather than a separate airing query: the viewer
  /// only cares about upcoming episodes of shows they are actually on.
  List<AnilistListEntry> get upcoming {
    final out = _entries
        .where((e) =>
            e.media.nextAiring != null &&
            (e.status == AnilistStatus.current.value ||
                e.status == AnilistStatus.planning.value ||
                e.status == AnilistStatus.repeating.value))
        .toList();
    out.sort(
      (a, b) => a.media.nextAiring!.airingAt.compareTo(b.media.nextAiring!.airingAt),
    );
    return out;
  }

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (!_service.isConnected) {
      _entries = const [];
      _error = null;
      notifyListeners();
      return;
    }
    if (_entries.isNotEmpty && !force) return;

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _entries = await _service.library();
    } catch (e) {
      _error = e is AnilistException ? e.message : 'Could not load your AniList list';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Marks one more episode watched.
  ///
  /// Optimistic: the card moves immediately and is rolled back if the write
  /// fails, because the round trip is long enough that an un-animated card
  /// reads as a dead button.
  Future<String?> bumpEpisode(AnilistListEntry entry) =>
      setProgress(entry, entry.progress + 1);

  /// Writes an explicit progress value.
  Future<String?> setProgress(AnilistListEntry entry, int progress) async {
    final token = _service.token;
    if (token == null) return 'AniList is not connected';
    if (progress < 0 || _busy.contains(entry.id)) return null;

    final previous = entry;
    _busy.add(entry.id);
    _replace(entry.copyWith(progress: progress));
    notifyListeners();

    try {
      final saved = await _service.api.saveProgress(
        token: token,
        mediaId: entry.media.id,
        progress: progress,
        status: _statusAfter(entry, progress),
      );
      // Trust the server's answer over the guess: AniList clamps progress to
      // the episode total and flips status to COMPLETED on the last one.
      _replace(entry.copyWith(progress: saved.progress, status: saved.status));
      return null;
    } catch (e) {
      _replace(previous);
      return e is AnilistException ? e.message : 'Could not save to AniList';
    } finally {
      _busy.remove(entry.id);
      notifyListeners();
    }
  }

  /// Moves an entry to another list.
  Future<String?> setStatus(AnilistListEntry entry, AnilistStatus status) async {
    final token = _service.token;
    if (token == null) return 'AniList is not connected';
    if (_busy.contains(entry.id)) return null;

    final previous = entry;
    _busy.add(entry.id);
    _replace(entry.copyWith(status: status.value));
    notifyListeners();

    try {
      final saved = await _service.api.saveProgress(
        token: token,
        mediaId: entry.media.id,
        progress: entry.progress,
        status: status.value,
      );
      _replace(entry.copyWith(progress: saved.progress, status: saved.status));
      return null;
    } catch (e) {
      _replace(previous);
      return e is AnilistException ? e.message : 'Could not save to AniList';
    } finally {
      _busy.remove(entry.id);
      notifyListeners();
    }
  }

  /// Completing the final episode should not leave the title on "Watching".
  static String? _statusAfter(AnilistListEntry entry, int progress) {
    final total = entry.media.episodes;
    if (total != null && total > 0 && progress >= total) {
      return AnilistStatus.completed.value;
    }
    if (entry.status == AnilistStatus.repeating.value) return null;
    if (entry.status == AnilistStatus.current.value) return null;
    return AnilistStatus.current.value;
  }

  void _replace(AnilistListEntry updated) {
    _entries = [
      for (final e in _entries)
        if (e.id == updated.id) updated else e,
    ];
  }
}
