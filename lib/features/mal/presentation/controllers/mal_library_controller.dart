import 'package:flutter/foundation.dart';

import 'package:soplay/features/mal/data/mal_constants.dart';
import 'package:soplay/features/mal/data/mal_tracker.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';

/// The viewer's MyAnimeList, and every edit made to it from this app.
///
/// Owns the list rather than handing it to each screen because two surfaces
/// show the same rows — the library tabs and the entry sheet — and a "+1" made
/// in one must be visible in the other immediately. Edits are applied locally
/// the moment the server confirms them, so nothing waits on a re-fetch.
class MalLibraryController extends ChangeNotifier {
  MalLibraryController({required MalService service}) : _service = service;

  final MalService _service;

  List<MalListEntry> _entries = const [];
  bool _loading = false;
  String? _error;

  /// Anime ids with a write in flight, so a row can show it and a double tap
  /// cannot send two conflicting edits.
  final Set<int> _busy = <int>{};

  List<MalListEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;
  bool isBusy(int animeId) => _busy.contains(animeId);
  bool get isConnected => _service.isConnected;
  MalViewer? get viewer => _service.viewer;

  /// Rows in one status, most recently touched first — which is the order a
  /// "what am I watching" list is actually useful in.
  List<MalListEntry> byStatus(String status) {
    final rows = [
      for (final e in _entries)
        if (e.status == status) e,
    ];
    rows.sort((a, b) {
      final at = a.updatedAt, bt = b.updatedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return rows;
  }

  MalListEntry? entryFor(int animeId) {
    for (final e in _entries) {
      if (e.anime.id == animeId) return e;
    }
    return null;
  }

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (!force && _entries.isNotEmpty) return;
    final token = _service.token;
    if (token == null) {
      _entries = const [];
      _error = null;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _entries = await _service.api.animeList(token);
    } catch (e) {
      _error = e is MalException ? e.message : 'Could not reach MyAnimeList';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> bumpEpisode(MalListEntry entry) =>
      setProgress(entry, entry.progress + 1);

  /// Sets progress, and moves the status when the episode count says so.
  ///
  /// Reaching the last episode completes the entry; touching a plan-to-watch or
  /// dropped row starts it. A rewatch is left alone — MAL models that as a flag
  /// on a completed entry, so any status sent during one ends the rewatch.
  Future<String?> setProgress(MalListEntry entry, int progress) async {
    final total = entry.anime.episodes;
    final clamped = progress < 0
        ? 0
        : (total != null && total > 0 && progress > total ? total : progress);
    if (clamped == entry.progress) return null;

    // The same decision the player makes when it reports an episode, and
    // deliberately the same code: two copies of "when does this become
    // completed, and when must a rewatch be left alone" would drift, and both
    // failures are invisible until someone's list is already wrong.
    final status = MalTracker.statusFor(
      current: entry.status,
      isRewatching: entry.isRewatching,
      episode: clamped,
      total: total,
    );

    return _write(entry, episodes: clamped, status: status);
  }

  Future<String?> setStatus(MalListEntry entry, String status) async {
    if (status == entry.status) return null;

    // Marking something completed with no progress recorded leaves a list
    // saying "finished, 0 of 12 watched". Fill it in, but only when the total
    // is known — an airing show has no honest number to use.
    final total = entry.anime.episodes;
    final episodes = status == MalStatus.completed &&
            total != null &&
            total > 0 &&
            entry.progress < total
        ? total
        : null;

    return _write(entry, status: status, episodes: episodes);
  }

  Future<String?> setScore(MalListEntry entry, int score) {
    final clamped = score.clamp(0, 10);
    if (clamped == entry.score) return Future.value(null);
    return _write(entry, score: clamped);
  }

  Future<String?> remove(MalListEntry entry) async {
    final token = _service.token;
    if (token == null) return 'MyAnimeList is not connected';
    if (!_busy.add(entry.anime.id)) return null;
    notifyListeners();

    try {
      await _service.api.deleteEntry(token: token, animeId: entry.anime.id);
      _entries = [
        for (final e in _entries)
          if (e.anime.id != entry.anime.id) e,
      ];
      return null;
    } catch (e) {
      return e is MalException ? e.message : 'Could not update MyAnimeList';
    } finally {
      _busy.remove(entry.anime.id);
      notifyListeners();
    }
  }

  /// One write path, so the busy set and the local replace cannot drift.
  Future<String?> _write(
    MalListEntry entry, {
    String? status,
    int? episodes,
    int? score,
  }) async {
    final token = _service.token;
    if (token == null) return 'MyAnimeList is not connected';
    if (!_busy.add(entry.anime.id)) return null;
    notifyListeners();

    try {
      final updated = await _service.api.updateEntry(
        token: token,
        anime: entry.anime,
        status: status,
        episodes: episodes,
        score: score,
      );
      if (updated != null) _replace(updated);
      return null;
    } catch (e) {
      return e is MalException ? e.message : 'Could not update MyAnimeList';
    } finally {
      _busy.remove(entry.anime.id);
      notifyListeners();
    }
  }

  void _replace(MalListEntry updated) {
    _entries = [
      for (final e in _entries)
        if (e.anime.id == updated.anime.id) updated else e,
    ];
  }
}
