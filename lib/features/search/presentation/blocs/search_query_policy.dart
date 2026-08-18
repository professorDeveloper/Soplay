import 'dart:async';

/// The single debounce + run policy for every search surface.
///
/// Both the single-source bloc and the cross-source controller used to carry
/// their own copy of this timer, which is how they drifted apart: same delay,
/// different behaviour on a re-typed query and on a run triggered from outside
/// the field (retry, provider-set change) while a debounce was still pending.
class SearchQueryPolicy {
  const SearchQueryPolicy._();

  static const Duration debounce = Duration(milliseconds: 450);

  /// A one-character query fans out to every selected source for almost no
  /// signal, so it never auto-runs. Submitting from the keyboard still does.
  static const int minLength = 2;

  static String normalize(String raw) => raw.trim();

  static bool runnable(String query) => normalize(query).length >= minLength;
}

class QueryDebouncer {
  Timer? _timer;
  String? _lastDispatched;

  bool get isPending => _timer?.isActive ?? false;

  /// Schedules [run] unless the query is too short or identical to the last one
  /// dispatched. Always cancels a pending run first.
  ///
  /// Returns whether a run was actually armed. Callers that show a spinner have
  /// to know: setting one before calling this left the UI searching forever on
  /// a one-character query, because nothing was ever dispatched to end it.
  bool schedule(String query, void Function(String query) run) {
    _timer?.cancel();
    final q = SearchQueryPolicy.normalize(query);
    if (!SearchQueryPolicy.runnable(q)) return false;
    if (q == _lastDispatched) return false;
    _timer = Timer(SearchQueryPolicy.debounce, () {
      _lastDispatched = q;
      run(q);
    });
    return true;
  }

  /// Runs [query] now, dropping any pending debounce. Used by the keyboard's
  /// Search key, which must not be swallowed by the dedupe.
  void runNow(String query, void Function(String query) run) {
    _timer?.cancel();
    final q = SearchQueryPolicy.normalize(query);
    if (q.isEmpty) return;
    _lastDispatched = q;
    run(q);
  }

  void cancel() => _timer?.cancel();

  /// Drops the dedupe key but leaves a pending run alone — used when a run
  /// failed, so retyping the same query is not swallowed as a duplicate.
  void forget() => _lastDispatched = null;

  /// Forgets the dedupe key so the same query runs again — a retry, a provider
  /// switch or a filter change all mean "the previous answer is void".
  void reset() {
    _timer?.cancel();
    _lastDispatched = null;
  }

  void dispose() => _timer?.cancel();
}
