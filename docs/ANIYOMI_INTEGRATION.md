# Aniyomi integration (Android-only)

Soplay can install **Aniyomi** anime extensions (`.apk` packages) from any
Aniyomi extension repository, on the device, alongside its normal providers and
the existing CloudStream sources. This document explains how it works, where
everything lives, and what is still pending.

> **Android only.** Aniyomi extensions are Android APKs whose classes are loaded
> with `DexClassLoader`. iOS has no equivalent, so the feature is hidden there
> and all calls no-op.
>
> **Why this is bigger than CloudStream.** CloudStream publishes its provider
> runtime as a reusable library (`com.github.recloudstream.cloudstream:library`
> on JitPack), so one Gradle line gives us `MainAPI`/extractors/`app` HTTP.
> Aniyomi does **not** publish a runtime: extensions compile against
> `compileOnly(libs.bundles.common)` (stub `extensions-lib`) and expect the host
> **app** to provide the real `AnimeHttpSource`/`NetworkHelper`/Injekt runtime at
> load time. So supporting Aniyomi means **vendoring that runtime** into the app
> (see Stage 2). It adds ~1.5–3 MB to the APK; the extensions themselves are
> downloaded at runtime and never bundled.
>
> **Licensing.** The Aniyomi runtime is GPL-3.0. Bundling it makes the app a
> derivative work — distribute source accordingly. (Sideload/APK; this content
> is not Play-Store friendly.)

---

## Status

| Stage | Scope | State |
|---|---|---|
| **1** | Separate Aniyomi section: install repos, download APKs, persist metadata, NSFW toggle, list/remove. | **Done** |
| **2** | Vendored runtime + reflection host + converter + provider routing so sources actually browse/play. | **Pending** |

Stage 1 installs and lists sources; it intentionally does **not** add `an:`
providers to the browse/search/detail flow yet, because nothing can resolve them
until the Stage 2 runtime exists. No broken entries appear in the provider sheet.

---

## How it works (high level)

```
index.min.json                       ┌── Flutter (Dart) ───────────────────────┐
        │  (admin/user pastes URL,    │  Profile ▸ Aniyomi Sources page          │
        │   or taps a recommended)    │  AniyomiChannel  (soplay/aniyomi)        │
        ▼                             └──────────────▲──────────────────────────┘
  AniyomiRepoManager (native)                        │ MethodChannel (JSON)
   • parse index.min.json (array of packages)        │
   • download .apk → filesDir/aniyomi/<pkg>-v<ver>.apk
   • persist metadata (id/name/lang/baseUrl/pkg/apkPath/nsfw)
        │                                            │
        ▼                                            │
  AniyomiHost (native)  ─────────────────────────────┘
   • register source metadata
   • providersJson() → an:<source.id>  (NSFW-filtered)
   • [Stage 2] DexClassLoader(apk) → reflect tachiyomi.animeextension.class
                → call getPopularAnime/getSearchAnime/getAnimeDetails/
                  getEpisodeList/getVideoList
        │
        ▼
  [Stage 2] vendored Aniyomi runtime (source-api + core/network + Injekt)
```

A registered Aniyomi source uses id `an:<source.id>` and `mode: client`,
`group: aniyomi` — kept separate from `cs:` (CloudStream) and normal providers.

---

## Index format (`index.min.json`)

A flat JSON array; each element is one extension **APK package** that can host
one or more `sources`:

```json
[
  {
    "name": "Aniyomi: AnimeOnsen",
    "pkg":  "eu.kanade.tachiyomi.animeextension.all.animeonsen",
    "apk":  "aniyomi-all.animeonsen-v14.10.apk",
    "lang": "all",
    "code": 10,
    "version": "14.10",
    "nsfw": 0,
    "sources": [
      { "name": "AnimeOnsen", "lang": "all",
        "id": "8542735178285060053",
        "baseUrl": "https://www.animeonsen.xyz", "versionId": 1 }
    ]
  }
]
```

- `version` prefix (`14`, `16`, …) = the **extensions-lib version** the source was
  built against. The vendored runtime must match (see Limitations).
- `id` = stable per-source id → our provider id `an:<id>`.
- APKs are served from `apk/` **next to** the index:
  `<index-url-dir>/apk/<apk>`. `AniyomiRepoManager.apkUrl()` derives this.

---

## Native (Android) — `android/app/src/main/kotlin/com/soplay/sozo/…`

| File | Role |
|---|---|
| `aniyomi/AniyomiRepoManager.kt` | Downloads `index.min.json`, caches each `.apk` in `filesDir/aniyomi/<pkg>-v<version>.apk`, persists per-repo metadata + display name + the NSFW flag in SharedPreferences (`aniyomi`). `addRepo` reports `current/total` install progress. |
| `aniyomi/AniyomiHost.kt` | Holds registered source metadata; `providersJson()` emits `an:<id>` provider cards and filters NSFW unless enabled. **Stage 2**: DexClassLoads an APK on first use and reflects its `AnimeSource`. |
| `MainActivity.kt` | Registers the `soplay/aniyomi` MethodChannel: `listProviders / ensureLoaded / listRepos / addRepo / removeRepo / isNsfwEnabled / setNsfwEnabled`. Calls run on the shared IO `CoroutineScope`, result posted on Main. |

### Lazy loading (planned, mirrors CloudStream)
- **First add** (`addRepo`): download every APK once, persist metadata.
- **Every launch** (`ensureLoaded`): re-register metadata only (instant) — no
  DexClassLoader, no network. Also re-applies the saved NSFW flag.
- **On use** (Stage 2): `AniyomiHost` DexClassLoads just that one APK the first
  time its source is opened.

### NSFW handling
- Per-package `nsfw` flag is persisted with each source's metadata.
- A single app-wide toggle (`setNsfwEnabled`) is stored in SharedPreferences.
- `providersJson()` skips NSFW sources unless the toggle is on. Default **off**.

---

## Flutter (Dart) — `lib/…`

| File | Role |
|---|---|
| `core/aniyomi/aniyomi_channel.dart` | Typed wrapper over `soplay/aniyomi` (Android-gated; iOS no-ops). Exposes the install-progress stream + NSFW get/set. |
| `features/aniyomi/presentation/pages/aniyomi_sources_page.dart` | "Aniyomi Sources" screen — add by URL, RECOMMENDED one-tap repos (Yuzono, Secozzi), 18+ toggle, installed list with delete. |
| `features/profile/presentation/pages/profile_page.dart` | Settings entry ("Aniyomi Sources"), shown only when `AniyomiChannel.isSupported`. |

### Recommended repos (in the page)
- **Yuzono Anime** — `https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json` (270+ sources, lib v14)
- **Secozzi** — `https://raw.githubusercontent.com/Secozzi/aniyomi-extensions/repo/index.min.json` (Jellyfin/Stremio/Torbox, lib v16)

---

## Stage 2 plan (runtime port)

Confirmed upstream layout (`github.com/aniyomiorg/aniyomi`, branch `main`):

1. **Vendor `source-api`** (`source-api/src/commonMain/kotlin/eu/kanade/tachiyomi/animesource/`):
   - `AnimeSource`, `AnimeCatalogueSource`, `AnimeSourceFactory`,
     `ConfigurableAnimeSource`, `UnmeteredSource`
   - `online/`: `AnimeHttpSource`, `ParsedAnimeHttpSource`, `ResolvableAnimeSource`
   - `model/`: `SAnime(Impl)`, `SEpisode(Impl)`, `Video`, `Hoster`, `AnimesPage`,
     `AnimeFilter(List)`, `AnimeUpdateStrategy`, `FetchType`
   - These are KMP (`expect`/`actual`) → adapt to plain Android Kotlin.
2. **Vendor `core/common` network** (`core/common/src/main/java/eu/kanade/tachiyomi/network/`):
   - `NetworkHelper`, `OkHttpExtensions`, `Requests`, `ProgressListener/Body`,
     `interceptor/*` (RateLimit, UserAgent, etc.)
3. **Add deps** to `android/app/build.gradle.kts`:
   - `org.jsoup:jsoup`, `org.jetbrains.kotlinx:kotlinx-serialization-json`,
     Injekt (`com.github.inorichi.injekt` / vendored), RxJava 1 (`io.reactivex:rxjava`
     — older sources still use `Observable` for `fetch*`).
   - `okhttp` + coroutines are already present (CloudStream library / existing dep).
4. **Injekt bootstrap**: register `NetworkHelper`, JSON, preferences so an
   extension's `Injekt.get<NetworkHelper>()` / `injectLazy()` resolves.
5. **Fill `AniyomiHost`**: `DexClassLoader(apkPath, optimizedDir, null, appClassLoader)`
   → read `tachiyomi.animeextension.class` from the APK manifest → instantiate
   (`AnimeSourceFactory` → `createSources()`; else the single class) → match by
   `source.id` → call the suspend `get*` methods (bridge old `fetch*` RxJava
   `Observable` → suspend where needed).
6. **Converter** (like CloudStream's `PluginHost` JSON mapping):
   - card → `{provider:'an:…', externalId, title, slug, contentUrl, thumbnail, type}`
   - `getAnimeDetails` + `getEpisodeList` → detail `{…, isSerial, episodes[…]}`
   - `getVideoList` → `{videoSources[{quality, videoUrl, type, headers}], subtitles[…]}`
     from `Video`/`Hoster` (`videoUrl`, `videoTitle`, `subtitleTracks`, `headers`).
7. **Routing**: add an `if (provider.startsWith('an:'))` branch to
   `home_repository_imp.dart`, `search_repository_imp.dart`,
   `detail_repository_impl.dart`, and append `an:` providers in
   `provider_bloc.dart` (via `ensureLoaded`) — exactly mirroring the `cs:` paths.
8. **Provider sheet**: add an `aniyomi` filter group in `providerGroup`.

---

## Limitations

- **Android only** (DEX). iOS hides the feature.
- **extensions-lib version skew** — a source built against lib `v16` may call
  APIs absent from a `v14`-targeted vendored runtime, and fail to load. Target
  one lib version first (Yuzono = v14) and expand. Expect a per-source success
  rate like CloudStream's (most work, a few don't).
- **Extractors** — Aniyomi bundles its shared extractors (`VoeExtractor`,
  `MegaCloudExtractor`, …) *inside each APK*, so they ship with the extension.
  But some need a JS engine (`JavaScriptEngine`/QuickJS) provided by the host —
  add that only if a target source requires it.
- **APK size** — vendoring the runtime adds ~1.5–3 MB (jsoup + serialization +
  runtime classes); +2–4 MB more if a JS engine is bundled.
- **GPL-3.0** obligations (see top).

---

## Testing (Stage 1)

1. `flutter run` (full build — native changes need a rebuild, not hot restart).
2. Profile ▸ **Aniyomi Sources** → tap a recommended repo (e.g. Yuzono) or paste
   an `index.min.json` URL.
3. Watch "Installing N / M extensions…", confirm the source count, toggle **18+**,
   delete a repo.
4. Logcat tag: `AniyomiRepo`.
5. Verify CloudStream sources, normal providers, my-list and continue-watching
   are unaffected (separate `an:` namespace + `aniyomi` SharedPreferences).
