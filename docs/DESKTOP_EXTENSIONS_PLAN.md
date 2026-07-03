# Desktop (Windows) — CloudStream / Aniyomi / Manga plan

> Status: **local bridge implemented** (Path A, run Android locally — no cloud).
> Run the debug Android app on an emulator/connected device; the Windows app
> fetches the same providers over HTTP. See **How to run** below. A hosted
> (Redroid) variant remains optional for a serverful setup.

## How to run (local bridge — no cloud, no cost)

The DEX extensions still need real Android — but that Android can be a **local
emulator or a phone plugged into your PC**, not a server. Steps:

1. **Run the debug Android app** on a local emulator (Android Studio AVD) or a
   connected device. On launch it auto-starts an HTTP bridge on port **8765**
   (`MainActivity.startBridgeServer()` → `BridgeServer.kt`, debug builds only).
2. **Expose it to the desktop:** `adb forward tcp:8765 tcp:8765` — now the PC's
   `http://127.0.0.1:8765` reaches the emulator/device's bridge.
3. **Point the desktop app at it:** add to `.env`:
   `EXTENSION_BRIDGE_URL=http://127.0.0.1:8765`
4. **Run the Windows app.** cs/aniyomi/manga providers now appear and play —
   the real Android (local) runs the plugins (incl. WebView/Cloudflare), the
   desktop is just an HTTP client. Add repos on the Android side (or via the
   desktop UI, which now routes `addRepo` to the bridge too).

Implementation: `android/.../BridgeServer.kt` (NanoHTTPD, mirrors the
MethodChannel methods 1:1) + `lib/core/extensions/extension_bridge.dart`
(Dio client) + the `Platform.isAndroid || ExtensionBridge.isEnabled` branch in
the three `lib/core/{cloudstream,aniyomi,manga}/*_channel.dart`. When
`EXTENSION_BRIDGE_URL` is unset, desktop is a no-op exactly as before.

> Note: this is a dev-grade flow (needs an emulator/phone running alongside).
> For a "just works, no emulator" setup, host the same bridge on a Redroid VM
> (Path A cloud, below) and point `EXTENSION_BRIDGE_URL` at it.

## The finding (why it's not a pure Flutter task)

`cs` (`.cs3`), `aniyomi` and `manga` extensions are **Android Dalvik DEX**
bytecode, loaded on-device via `DexClassLoader` / `PathClassLoader` and linked
against the vendored `eu.kanade.tachiyomi.*` + CloudStream `library` API and the
**Android framework** (`android.*`, a real **WebView** for Cloudflare /
`WebViewResolver`). Native hosts live in
`android/app/src/main/kotlin/com/soplay/sozo/{cloudstream,aniyomi,manga}/`
and are exposed to Dart via the `soplay/{cloudstream,aniyomi,manga}` MethodChannels
(`lib/core/{cloudstream,aniyomi,manga}/*_channel.dart`, all `Platform.isAndroid`-gated).

**Windows cannot run these directly.** A JVM can't load DEX; even converted, the
code hits the `android.*` / WebView wall. `jni` doesn't help (it runs JVM, not DEX;
it's only a transitive dep of `path_provider_android`). This matches the project's
own `docs/CLOUDSTREAM_IOS_SERVER_PLAN.md`.

Note: the **JS/backend providers** (AsilMedia, vidapi, … via `lib/core/js/`) already
work on Windows — only the DEX extension systems don't.

## The two real paths

### Path A — Redroid bridge (all extensions, needs a server) — RECOMMENDED for full support
Run real Android in the cloud and make desktop an HTTP client. Same as the iOS plan
(`CLOUDSTREAM_IOS_SERVER_PLAN.md`), Windows is just another client.

In-repo work (**I can build all of this**):
1. **Headless Android APK / build flavour** — wrap the existing `PluginHost` /
   `AniyomiHost` / `MangaHost` in an embedded HTTP server (NanoHTTPD/Ktor). Endpoints
   return the SAME JSON the MethodChannels already emit: `/providers`, `/mainpage`,
   `/section`, `/search`, `/load`, `/loadlinks`, `/repo` (per system). ~150 lines,
   hosts unchanged.
2. **Desktop HTTP client** — in `lib/core/extensions/extension_bridge.dart` (new),
   a Dio client to the bridge; wire each `*_channel.dart` so on non-Android with a
   configured `EXTENSION_BRIDGE_URL` it routes to the bridge, else current no-op.
   JSON shapes already match soplay models → repositories unchanged.
3. **Node proxy + Redis cache** (in the existing backend) — reverse-proxy to Redroid,
   cache `mainpage`/`search`/`load` 5–10 min, never cache `loadlinks`.

Infra work (**you provision**):
- A KVM VPS running `redroid/redroid:13` (needs `binder`/`ashmem` kernel modules —
  not Lambda/Cloud Run). ~2–4 GB RAM, ~€4–10/mo. `adb install` the headless APK.
- ⚠️ Datacenter IPs get Cloudflare-blocked under load → may need residential proxies
  (often the biggest real cost).

### Path B — Dart/JS reimplementation (serverless, per-provider)
Reimplement the **specific** providers you need in Dart/JS (like the existing JS
providers). Runs natively on Windows, no server, no cost. Trade-off: manual per
provider; NOT "all `.cs3`/aniyomi/manga automatically". Needs you to name the
providers to port.

## Decision needed
- Want **all** cs/aniyomi/manga on desktop → **Path A** (needs a small VPS).
- Want **a few providers**, no server/cost → **Path B** (name them).
- Otherwise → keep Android-only; desktop uses the working JS/backend providers.

Once chosen, execution is straightforward — the in-repo parts are all buildable here;
only the Redroid VPS is external.
