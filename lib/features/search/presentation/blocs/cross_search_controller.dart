import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riasdxd/features/search/domain/entities/cross_search_result.dart';
import 'package:riasdxd/features/search/domain/services/cross_search_engine.dart';

/// Drives one cross-search page: debounces input, runs the engine, collects
/// results incrementally, and cancels the previous run on every new query.
class CrossSearchController extends ChangeNotifier {
  CrossSearchController({required this.engine, required List<ProviderRef> set})
      : _set = set;

  final CrossSearchEngine engine;
  List<ProviderRef> _set;

  Timer? _debounce;
  StreamSubscription<ProviderSearchResult>? _sub;
  int _token = 0;

  String _query = '';
  bool _searching = false;
  final Map<String, ProviderSearchResult> _results = {};

  String get query => _query;
  bool get searching => _searching;
  List<ProviderRef> get providerSet => _set;

  /// Number of search legs (server providers collapse into one).
  int get expectedLegs {
    var legs = 0;
    var hasServer = false;
    for (final p in _set) {
      if (p.kind == ProviderKind.server) {
        hasServer = true;
      } else {
        legs++;
      }
    }
    return legs + (hasServer ? 1 : 0);
  }

  int get completedLegs => _results.length;
  int get totalItems => _results.values.fold(0, (s, r) => s + r.items.length);
  int get sourcesWithResults =>
      _results.values.where((r) => r.hasItems).length;

  /// Results ordered so sources with hits come first, then empty/timeout/error.
  List<ProviderSearchResult> get results {
    final out = _results.values.toList();
    int rank(ProviderSearchResult r) => switch (r.status) {
          ProviderSearchStatus.ok => 0,
          ProviderSearchStatus.empty => 1,
          ProviderSearchStatus.timeout => 2,
          ProviderSearchStatus.error => 3,
        };
    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  }

  /// How many distinct providers returned a title (normalized title + year).
  /// Only exact normalized-key matches count — no fuzzy merging.
  Map<String, int> _crossSourceCounts = const {};
  int crossSourceCount(String title, int? year) =>
      _crossSourceCounts[_key(title, year)] ?? 0;

  static String _key(String title, int? year) =>
      '${title.trim().toLowerCase()}|${year ?? ''}';

  void onQueryChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    _query = trimmed;
    if (trimmed.isEmpty) {
      _cancel();
      _results.clear();
      _crossSourceCounts = const {};
      _searching = false;
      notifyListeners();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(trimmed));
  }

  void setProviderSet(List<ProviderRef> set) {
    _set = set;
    if (_query.isNotEmpty) _run(_query);
  }

  void retry() {
    if (_query.isNotEmpty) _run(_query);
  }

  void _run(String q) {
    _cancel();
    final token = ++_token;
    _results.clear();
    _crossSourceCounts = const {};
    _searching = _set.isNotEmpty;
    notifyListeners();
    if (_set.isEmpty) return;

    _sub = engine.search(set: _set, query: q).listen(
      (result) {
        if (token != _token) return;
        _results[result.provider.id] = result;
        _recomputeCrossCounts();
        notifyListeners();
      },
      onDone: () {
        if (token != _token) return;
        _searching = false;
        notifyListeners();
      },
    );
  }

  void _recomputeCrossCounts() {
    final counts = <String, Set<String>>{};
    for (final r in _results.values) {
      for (final m in r.items) {
        counts
            .putIfAbsent(_key(m.title, m.year), () => <String>{})
            .add(r.provider.id);
      }
    }
    _crossSourceCounts = {
      for (final e in counts.entries) e.key: e.value.length,
    };
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel();
    super.dispose();
  }
}
