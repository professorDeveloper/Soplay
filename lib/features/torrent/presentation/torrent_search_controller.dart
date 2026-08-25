import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/torrent_search_repository.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';

/// Drives the torrent search page.
///
/// A [ChangeNotifier] rather than a bloc, matching `CrossSearchController`:
/// this is one screen's transient state with no events worth replaying, and
/// nothing outside the page reads it.
///
/// The one piece of real logic is request ordering. Searching four trackers
/// takes seconds, the user keeps typing, and a slow response from an abandoned
/// query must never overwrite a newer one — so every search carries a sequence
/// number and stale results are dropped on arrival.
class TorrentSearchController extends ChangeNotifier {
  TorrentSearchController({required TorrentSearchRepository repository})
      : _repository = repository;

  final TorrentSearchRepository _repository;

  int _sequence = 0;
  CancelToken? _cancelToken;
  Timer? _debounce;

  String _term = '';
  TorrentQuery _query = const TorrentQuery(term: '');
  TorrentFilters _filters = const TorrentFilters();
  Set<String>? _enabledIndexers;
  bool _nsfwAllowed = false;

  List<TorrentResult> _results = const [];
  bool _loading = false;
  Object? _error;

  String get term => _term;
  TorrentQuery get query => _query;
  TorrentFilters get filters => _filters;
  List<TorrentResult> get results => _results;
  bool get loading => _loading;
  Object? get error => _error;

  /// True once a search has run, so the page can tell "nothing searched yet"
  /// apart from "searched and found nothing" — they need different empty
  /// states.
  bool get hasSearched => _sequence > 0;

  List<TorrentIndexer> get indexers => _repository.indexers;

  Set<String> get enabledIndexers =>
      _enabledIndexers ??
      _repository.indexers
          .where((i) => !i.isNsfw)
          .map((i) => i.id)
          .toSet();

  /// Typing runs a debounced search; submitting runs one immediately.
  ///
  /// 450 ms is longer than a normal in-app debounce on purpose — each keystroke
  /// that gets through costs four requests to third-party trackers, some of
  /// which rate-limit.
  void onTermChanged(String value) {
    _term = value;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _cancelInFlight();
      _results = const [];
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), search);
  }

  void setCategory(TorrentCategory category) {
    if (_query.category == category) return;
    _query = _query.copyWith(category: category, page: 1);
    notifyListeners();
    if (_term.trim().isNotEmpty) search();
  }

  void setSort(TorrentSort sort) {
    if (_query.sort == sort) return;
    _query = _query.copyWith(sort: sort, page: 1);
    notifyListeners();
    if (_term.trim().isNotEmpty) search();
  }

  void setFilters(TorrentFilters filters) {
    _filters = filters;
    notifyListeners();
    if (_term.trim().isNotEmpty) search();
  }

  void setEnabledIndexers(Set<String> ids) {
    _enabledIndexers = ids;
    notifyListeners();
    if (_term.trim().isNotEmpty) search();
  }

  set nsfwAllowed(bool value) {
    if (_nsfwAllowed == value) return;
    _nsfwAllowed = value;
    notifyListeners();
  }

  Future<void> search() async {
    final term = _term.trim();
    if (term.isEmpty) return;

    _cancelInFlight();
    final sequence = ++_sequence;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await _repository.search(
        _query.copyWith(term: term),
        filters: _filters,
        enabledIds: enabledIndexers,
        nsfwAllowed: _nsfwAllowed,
        cancelToken: cancelToken,
      );
      // A newer search started while this one was in flight.
      if (sequence != _sequence) return;
      _results = results;
    } catch (e) {
      if (sequence != _sequence) return;
      _error = e;
      _results = const [];
    } finally {
      if (sequence == _sequence) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _cancelInFlight() {
    _debounce?.cancel();
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('superseded');
    }
    _cancelToken = null;
  }

  @override
  void dispose() {
    _cancelInFlight();
    super.dispose();
  }
}
