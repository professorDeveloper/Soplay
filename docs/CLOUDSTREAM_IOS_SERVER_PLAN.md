# CloudStream on iOS — Server-Side Plan (Redroid)

> Goal: CloudStream `.cs3` providers working in the **iOS** soplay app (TestFlight →
> App Store). Android keeps running plugins **on-device** (unchanged); iOS routes
> the same calls to a hosted Android runtime over HTTP.

## Why not "pure serverless" / in-app JVM

- `.cs3` = **Dalvik DEX** bytecode, not JVM bytecode. Loaded via
  `dalvik.system.DexClassLoader` / `PathClassLoader` — **Android-only** APIs. A
  plain JVM (AWS Lambda, Cloud Run, Cloud Functions) cannot load them.
- Plugins reference **Android framework** (`android.*`, `WebView`) + need a real
  **WebView** for Cloudflare/`WebViewResolver`. None exist on a bare JVM or iOS.
- iOS bans downloaded/executed code (App Store **2.5.2**) **and** blocks JIT at the
  OS level (true even on TestFlight). So an in-app JVM + `.cs3` is impossible.

**Conclusion:** the only thing that *definitely* runs arbitrary `.cs3` is **real
Android**. So we run Android in the cloud (Redroid) and expose it as an API. This
is container-based ("managed server"), not Lambda-serverless.

## Architecture

```
iOS (TestFlight)
   │  HTTPS  /cloudstream/getMainPage?provider=..&page=1   (+ search/load/loadLinks)
   ▼
Node backend (existing)  ──  proxy + Redis cache + repo registry
   │  internal HTTP
   ▼
Redroid (Android 13 in Docker, on a KVM VM)
   └─ "soplay-headless" APK
        • reuses PluginHost.kt / RepoManager.kt (already written)
        • tiny NanoHTTPD server exposing listProviders/getMainPage/search/load/loadLinks
        • real WebView  → CloudflareKiller / WebViewResolver WORK
        • real DexClassLoader → any .cs3 loads, exactly like the phone
```

Key win: the **same native code that already works on the phone** runs in Redroid,
so behaviour matches 1:1 ("definitely works").

## Components & steps

1. **Headless APK** (new, small Android app or build flavour)
   - Wrap `PluginHost` in NanoHTTPD (or Ktor embedded). Endpoints return the same
     JSON the MethodChannel already produces:
     - `GET /providers`
     - `GET /mainpage?provider=&page=`
     - `GET /section?provider=&data=&page=`
     - `GET /search?provider=&q=`
     - `GET /load?provider=&url=`
     - `GET /loadlinks?provider=&data=`
     - `POST /repo {url}` / `DELETE /repo {url}` / `GET /repos`
   - ~150 lines; PluginHost/RepoManager unchanged.

2. **Redroid VM**
   - Docker `redroid/redroid:13` on a **KVM VPS** (Hetzner CX22 ~€4/mo, Fly.io
     machine, etc.). Needs `binder`/`ashmem` kernel modules → **not** Lambda/Cloud Run.
   - `adb install soplay-headless.apk`; auto-start the HTTP service on boot.
   - ~2–4 GB RAM per instance.

3. **Node backend** (`/cloudstream/*`)
   - Reverse-proxy to the Redroid instance(s).
   - **Redis cache**: `getMainPage`/`search`/`load` for 5–10 min (big capacity
     multiplier). Do **not** cache `loadLinks` long (links expire).
   - Repo registry: which repos are installed (shared, or per-user later).
   - Optional: round-robin across multiple Redroid instances.

4. **iOS Dart client**
   - In `CloudStreamChannel`: when `Platform.isIOS`, call the backend HTTP API
     instead of the native MethodChannel. Android stays native/on-device.
   - JSON shapes already match soplay models → repositories need no change.

## Capacity & cost (rough)

- One 2–4 GB Redroid VM + Redis cache: a few **hundred light users** browsing
  (cache hits dominate). `loadLinks` (pressing play) is the heavy moment.
- Scale out = more Redroid instances behind the Node proxy.
- ⚠️ Datacenter IPs get **Cloudflare-blocked / rate-limited**; heavy use may need
  **residential proxies** (often the biggest real cost, not the VM).

## Alternative (truly serverless, no server cost, limited scope)

Reimplement the **specific** providers you need in **Dart** (like the existing
JS/zangetsu providers). Runs natively on iOS, no backend. Trade-off: manual per
provider, not "all `.cs3` automatically".

## Decision

- Want **all CloudStream on iOS** → **Redroid** (only path that definitely works; needs a VM).
- Want **no server / a few providers** → **Dart reimplementation**.

## Build order (if Redroid chosen)

1. Headless APK (PluginHost + NanoHTTPD) — verify locally with `curl`.
2. Redroid VM up; install APK; reach the endpoints over the LAN.
3. Node `/cloudstream/*` proxy + Redis cache.
4. iOS `CloudStreamChannel` HTTP branch; test on TestFlight.
5. Add residential proxy + multi-instance only if/when load needs it.
