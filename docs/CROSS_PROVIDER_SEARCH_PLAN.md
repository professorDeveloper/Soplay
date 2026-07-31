# Cross-Provider Search + Universal Tracker Plan

## Goal / differentiation

Sozo's unique asset is its **multi-provider plugin architecture** (server +
CloudStream `cs:` + Aniyomi `an:` + manga `mn:` + JS extractors). No mainstream
app unifies these. Today, search only queries the **current** provider
(`search_repository_imp.dart:60` uses `_currentProvider` only) — to search
elsewhere the user must switch providers first. This plan turns that limitation
into the flagship differentiator, **without ANR/freezes**, even with 200+
installed CloudStream providers.

Three features, one shared engine:

1. **Cross-provider search** — search a user-selected set of providers at once,
   results streamed in, grouped by provider.
2. **Detail → "Find on other sources"** — from a title, find the same title
   across the selected set and jump to whichever source has it.
3. **Universal tracker** (phased) — follow a title, get notified when any
   source has a new episode; unified "continue watching".

## Hard constraint: no freeze with 200+ providers

The user's #1 concern. The design is freeze-proof by construction:

- **Never fan out to all providers.** The user curates a **Search Set** (a small
  persisted subset). Cross-search only ever hits that set.
- **Bounded concurrency.** A pool runs at most `N` (default **5**) provider
  searches at a time; the rest queue.
- **Per-provider timeout.** Each provider search is wrapped in a ~**10s**
  timeout; a slow/broken provider is dropped, never blocks the batch.
- **Incremental streaming.** Results are emitted per provider **as they arrive**
  via a `Stream` — the UI never waits for the slowest one.
- **Cancellation.** A new query or page dispose bumps an exec token and cancels
  in-flight work (the `_execToken` pattern already in `SearchBloc`).
- **Per-provider error isolation.** One provider throwing never fails the batch.
- **Off-main-thread already.** Native `cs:`/`an:`/`mn:` searches run off the
  platform thread (`MainActivity.csAsync`), and JS extractor runs in a headless
  webview — so the pool only guards against *overwhelming the device*, not UI
  thread blocking.

## Architecture (fits the existing clean architecture)

### Reusable per-provider dispatch

Extract the provider dispatch currently inlined in
`SearchRepositoryImp.searchMovies` (`search_repository_imp.dart:60-104`) into a
single reusable function that can search **any** provider id (not just current):

```
Future<Result<SearchModel>> searchOneProvider(String providerId, String query, {int page = 1})
```

Dispatch (same rules as today):
- `cs:<n>` → `CloudStreamChannel.search(n, query, page)`
- `an:<n>` → `AniyomiChannel.search(n, query, page)`
- `mn:<n>` → `MangaChannel.search(n, query, page)`
- extractor provider (`mode != server` && has extractor) → `js.trySearch(id, query, page)`
- server providers → one `SearchDataSource.searchMovies` call (backend is
  provider-agnostic; represented as a single "Sozo" group, not per server id)

`SearchRepositoryImp.searchMovies` then becomes a thin wrapper:
`searchOneProvider(_currentProvider ?? '', query, page)`.

### The engine

`lib/features/search/domain/services/cross_search_engine.dart`

```
class ProviderSearchResult {           // one provider's outcome
  final ProviderRef provider;          // id, name, icon
  final List<MovieEntity> items;       // may be empty
  final ProviderSearchStatus status;   // pending | ok | timeout | error | empty
}

Stream<ProviderSearchResult> CrossSearchEngine.search({
  required List<ProviderRef> set,      // the curated Search Set
  required String query,
  int concurrency = 5,
  Duration perProviderTimeout = const Duration(seconds: 10),
  CancelToken? cancel,
});
```

Implementation: a concurrency pool draining `set`, each task calling
`searchOneProvider(...).timeout(...)`, yielding a `ProviderSearchResult` as each
completes (including `timeout`/`error`/`empty` so the UI can show status chips).

### Presentation (grouped + high-precision cross-source badge)

`CrossSearchBloc` consumes the stream and holds a growing
`Map<providerId, ProviderSearchResult>` plus derived state:
- **Grouped view:** one section per provider, appearing as it resolves, with a
  status chip (spinner / count / "timed out" / "no results").
- **"Also on N sources" badge:** computed cheaply and **safely** — group items
  by a normalized key `slug(title) + '|' + year`; only **exact** normalized
  matches merge into the badge. No fuzzy matching → no wrong merges. (A later,
  opt-in "merged view" can reuse this key.)

### Search Set selection (anti-200)

- Persist selected provider ids in Hive: key `cross_search_provider_ids`
  (mirrors the bridge's `shared_ids` precedent in `MainActivity.kt:515`).
- Source of truth for the picker: `ProviderBloc` → `ProviderLoaded.providers`
  (`provider_state.dart:14`), already the union of backend + `cs:`/`an:`/`mn:`.
- UX: a "Search sources" multi-select sheet (checklist + search filter + "select
  all in category" but capped with a warning past ~15). Default set = current
  provider + any previously-picked; empty set prompts the user to choose.
- Guardrail: if the set is large, show a non-blocking hint ("searching 40
  sources may be slow") — but the pool + timeouts keep it safe regardless.

## Feature 2 — Detail → "Find on other sources"

On the detail page, an action runs `CrossSearchEngine.search(set, title)` and
shows a sheet: which sources have this title (using the normalized-key match),
each row → open that provider's detail/player. Reuses the engine verbatim; no
new resolution logic.

## Feature 3 — Universal tracker (phased, after 1–2)

- `Follow` a title → store `{title, normalizedKey, lastKnownEpisode, set}` in
  Hive (new `followed` box).
- A bounded check (on app open + optional periodic WorkManager) runs the engine
  for followed titles across their set, compares episode counts, and fires a
  local notification via the existing `flutter_local_notifications` +
  notifications feature.
- Unified "continue watching" across providers keys off the same normalized key
  over the existing history store.
- Same ANR rules (bounded, timed, incremental, cancellable).

## Files

### Add
```
lib/features/search/domain/services/cross_search_engine.dart      # pool + timeout + stream
lib/features/search/domain/entities/provider_search_result.dart   # per-provider result + status
lib/features/search/data/services/provider_search_dispatch.dart   # searchOneProvider(id, q, page)
lib/features/search/presentation/blocs/cross_search_bloc.dart      # consumes the stream
lib/features/search/presentation/pages/cross_search_page.dart      # grouped incremental UI
lib/features/search/presentation/widgets/search_set_sheet.dart     # provider multi-select
```

### Modify
```
lib/features/search/data/repositories/search_repository_imp.dart  # reuse dispatch; add per-id path
lib/core/extractor/provider_manager.dart                          # expose read-only providers list
lib/core/storage/hive_service.dart                                # cross_search_provider_ids get/set
lib/features/search/presentation/pages/search_page.dart           # entry to cross-search + set sheet
lib/features/detail/presentation/pages/detail_page.dart           # "Find on other sources" action
lib/core/di/injection.dart                                        # register engine/bloc
```

## Phases

- **P1 — Engine core:** `searchOneProvider` dispatch extraction +
  `CrossSearchEngine` (pool/timeout/stream/cancel) + Hive search-set. Unit-test
  the pool with fake providers (concurrency cap, timeout drop, cancellation).
- **P2 — Cross-search UI:** `CrossSearchBloc` + grouped incremental page +
  Search Set sheet + entry point on the search page.
- **P3 — Detail find-on-source:** action + results sheet (reuses engine).
- **P4 — Universal tracker:** follow store + episode-diff check + notifications
  + cross-provider continue-watching.

## Performance guarantees (acceptance)

- [ ] With a 50-provider set, the search page stays at 60fps; groups stream in;
      no ANR/jank while native searches run.
- [ ] A provider that hangs is dropped at 10s; the rest still render.
- [ ] Typing a new query cancels the previous batch (no stale results).
- [ ] Concurrency never exceeds the cap (verified via test counter).
- [ ] "Also on N sources" never wrongly merges different titles (exact
      normalized-key only).
- [ ] Leaving the page cancels all in-flight provider searches.
```
