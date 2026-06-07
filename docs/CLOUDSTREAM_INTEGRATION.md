# CloudStream integration (Android-only)

Soplay can install and run **CloudStream** extensions (`.cs3` plugins) from any
CloudStream repository, on the device, alongside its normal providers. This
document explains how it works and where everything lives.

> **Android only.** `.cs3` files are compiled Kotlin/DEX, loaded with
> `DexClassLoader`. iOS has no equivalent, so the feature is hidden there and
> all calls no-op.
>
> **Licensing.** The CloudStream runtime is GPL-3.0. Bundling it makes the app a
> derivative work — distribute source accordingly. (Sideload/APK; CloudStream
> content is not Play-Store friendly.)

---

## How it works (high level)

```
repo.json / plugins.json            ┌── Flutter (Dart) ───────────────────────┐
        │  (admin/user pastes URL)  │  Settings ▸ CloudStream Sources page     │
        ▼                           │  CloudStreamChannel  (soplay/cloudstream)│
  RepoManager (native)              │  FramePreviewService (soplay/preview)    │
   • download .cs3 → filesDir/cs3   └──────────────▲──────────────────────────┘
   • persist metadata (name/icon/path)             │ MethodChannel (JSON)
        │                                           │
        ▼                                           │
  PluginHost (native)  ───────────────────────────►┘
   • PathClassLoader(file, appClassLoader)
   • read manifest.json → load Plugin → registerMainAPI()
   • providers land in APIHolder.allProviders
        │
        ▼
  CloudStream `library` runtime (com.github.recloudstream.cloudstream:library)
   • MainAPI (getMainPage/search/load/loadLinks), extractors, `app` HTTP, …
```

A registered CloudStream provider appears in the normal provider list with id
`cs:<MainAPI.name>` and `mode: client`. The repositories route all of its
catalog + playback calls to the device (`CloudStreamChannel`) instead of the
backend.

---

## Native (Android) — `android/app/src/main/kotlin/com/soplay/sozo/…`

| File | Role |
|---|---|
| `build.gradle.kts` + root `build.gradle.kts` | JitPack repo + `implementation("com.github.recloudstream.cloudstream:library:v4.7.0")` (the provider runtime — MainAPI/APIHolder/extractors/`app` HTTP). Also `packaging { resources { excludes … } }` for okhttp/jspecify META-INF clashes. |
| `cloudstream/PluginHost.kt` | Loads `.cs3` via `PathClassLoader`, registers providers, and adapts the CloudStream surface to soplay's JSON shapes. **Lazy**: keeps only metadata at startup; a plugin is DexClassLoaded on first use. |
| `cloudstream/RepoManager.kt` | Downloads repos (`repo.json {pluginLists}` or direct `plugins.json[]`), caches `.cs3` in `filesDir/cs3/<name>@<ver>.cs3`, and persists per-repo metadata + display name in SharedPreferences (`cloudstream`). |
| `lagradost/cloudstream3/plugins/Plugin.kt` | Minimal clean-room `Plugin` base class. Plugins subclass `com.lagradost.cloudstream3.plugins.Plugin` (in CloudStream's *app* module, not the library), so we provide a compatible one extending the library's `BasePlugin`. |
| `preview/FramePreview.kt` | Seek-preview generator: `MediaMetadataRetriever` samples a frame at a position → scaled JPEG. (CloudStream providers ship no thumbnails; CloudStream itself generates them the same way.) |
| `MainActivity.kt` | Registers two MethodChannels: `soplay/cloudstream` (listProviders / ensureLoaded / addRepo / removeRepo / listRepos / getMainPage / getSection / search / load / loadLinks) and `soplay/preview` (open / frame / close). CloudStream calls are `suspend` → run on an IO `CoroutineScope`, result posted on Main. |

### Lazy loading (important)
Loading 70+ plugins on every launch is slow (each `load()` may hit the network).
Instead:
- **First add** (`addRepo`): download + load each plugin once to discover its
  provider names/icons; persist metadata (`provider, icon, internalName, cs3Path`).
- **Every launch** (`ensureLoaded`): only re-register metadata (instant) — no
  DexClassLoader, no network.
- **On use**: `apiByName()` calls `ensurePluginLoaded()`, which DexClassLoads
  just that one plugin the first time its provider is opened.

### Output mapping (the "converter")
`PluginHost` emits JSON matching soplay's existing models, so the Flutter side
reuses its normal entities:
- card → `{provider:'cs:…', externalId, title, slug, contentUrl, thumbnail, type}`
- `load()` → detail `{title, description, thumbnail, banner, year, duration,
  genres, cast, related, isSerial, episodes[…]}` (Movie → 1 episode with
  `dataUrl`; TvSeries/Anime → episode list with `data` refs). `related` falls
  back to a title search when the provider returns no recommendations.
- `loadLinks()` → `{videoUrl, type, headers, videoSources[{quality:'<host> · <res>p',
  videoUrl, type, isDefault, accessible, headers}], subtitles[{label, file, default}]}`
  with URL/subtitle de-duplication.

---

## Flutter (Dart) — `lib/…`

| File | Role |
|---|---|
| `core/cloudstream/cloudstream_channel.dart` | Typed wrapper over `soplay/cloudstream` (Android-gated; iOS no-ops). |
| `core/preview/frame_preview_service.dart` | Wrapper over `soplay/preview`; frames bucketed (5 s) + cached. |
| `features/cloudstream/presentation/pages/cloudstream_sources_page.dart` | "CloudStream Sources" settings screen — add by URL, list (name + url), delete. |
| `features/profile/presentation/bloc/provider_bloc.dart` | Appends `cs:` providers (via `ensureLoaded`) to the live provider list. |
| `features/profile/presentation/pages/profile_page.dart` | Settings entry; provider sheet filter groups (All / Cloud / Hybrid / Local / CloudStream via `providerGroup`), session-persisted filter, scroll-to-selected, near-full-screen snap. |
| `features/home/.../home_repository_imp.dart`, `features/search/.../search_repository_imp.dart`, `features/detail/.../detail_repository_impl.dart` | Each has an `if (provider.startsWith('cs:'))` branch routing home/viewAll/search/detail/episodes/resolveMedia to `CloudStreamChannel`, then `Model.fromJson(...)`. Genres short-circuit to empty for `cs:`. |
| `features/detail/.../player_page.dart` | `_GeneratedFramePreview` shows native frames during scrub/slider when there's no VTT/storyboard (most CloudStream sources). |

CloudStream content uses stable ids (`cs:<name>` + the plugin `load` url as
`contentUrl`), so my-list and continue-watching work with no special handling.

---

## Repository format

`repo.json`:
```json
{ "name": "My Repo", "pluginLists": ["https://…/plugins.json"] }
```
`plugins.json` (also accepted directly):
```json
[ { "name": "Provider", "internalName": "Provider", "url": "https://…/Provider.cs3",
    "version": 7, "iconUrl": "https://…/icon.png", "language": "en", "tvTypes": ["Movie"] } ]
```

---

## Limitations

- **Android only** (DEX). iOS hides the feature.
- **A few advanced plugins fail to load** when they reference app-module classes
  absent from the `library` (e.g. `SyncRepo`, `CloudStreamApp`, `MainActivity` →
  TorraStream, Ultima, StremioX). Most (≈70/73 in the phisher repo) work. More
  clean-room stubs (like `Plugin.kt`) could be added if needed.
- **Per-provider success** depends on each plugin/site staying up and its host
  extractors working.
- **Seek preview** is generated from the stream (`MediaMetadataRetriever`):
  great for progressive MP4 (HubCloud/DriveSeed direct files), best-effort for
  HLS (may show nothing — graceful).
- **GPL-3.0** obligations (see top).

---

## Testing

1. `flutter run` (full build — native changes need a rebuild, not hot restart).
2. Settings ▸ **CloudStream Sources** → add e.g.
   `https://raw.githubusercontent.com/phisher98/cloudstream-extensions-phisher/refs/heads/builds/repo.json`.
3. Provider sheet → **CloudStream** filter → pick a provider → home → detail →
   episodes → **play**. Scrub to see generated frame previews (MP4 sources).
4. Logcat tags: `CloudStreamHost`, `CloudStreamRepo`, `FramePreview`.
5. Verify existing providers, my-list and continue-watching are unaffected.
