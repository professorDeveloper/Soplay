# Sozo Chromecast Plan (Android) — Cast-through-Proxy

## Goal

Add a Chromecast ("Cast to TV") option to the Android player that works for the
**majority** of Sozo's real sources — including the ones that need custom
headers, a `Referer`, Cloudflare clearance, or an IP-bound signed manifest — not
just plain public URLs.

The naive approach (hand the Chromecast the raw `videoUrl`) only works for a
small minority of sources, because a Chromecast fetches the media **itself** and
the stock Default Media Receiver will not reliably send the custom
`Referer`/`Origin`/`User-Agent`/`Cookie` headers that most Sozo sources require,
and cannot reproduce the phone's Cloudflare `cf_clearance` cookie (UA/IP-bound).

## One-sentence architecture

Keep the phone in the request path: cast **through** a LAN-exposed version of the
existing `LocalHlsProxy`, so the phone performs all upstream auth
(headers/cookies/CF/RC4 signing) and the Chromecast only ever fetches a plain,
token-protected `http://<phone-lan-ip>:<port>/...` URL that the stock Default
Media Receiver can play.

```text
Chromecast (Default Media Receiver CC1AD845)
  GET http://192.168.1.50:<port>/c/<token>/hls/<sid>/master.m3u8   (no special headers)
   -> Sozo LocalHlsProxy on the phone (bound to 0.0.0.0, token-gated)
        -> upstream CDN with the phone's cookies / CF-clearance / Referer / RC4 headers
        <- rewritten manifest whose segment URLs point back at the proxy (token preserved)
```

Because the proxy is a transparent pass-through when a source needs no special
handling, **one code path** covers everything: plain URLs, headered URLs,
CF-gated URLs, and IP-bound signed HLS.

## The key insight

`LocalHlsProxy` (`lib/core/player/local_hls_proxy.dart`) already:

- injects the provider's upstream headers and (via the injected CF/cookie-jar
  `Dio`) the phone's Cloudflare clearance cookie + matching UA
  (`local_hls_proxy.dart:118-129, 139-147`);
- rewrites HLS manifests so **every** variant/segment/`URI="…"` (including
  cross-origin CDNs, base64-tagged under `/_h/`) routes back through the proxy
  (`local_hls_proxy.dart:249-297`);
- streams non-manifest bodies with `Range`/`Content-Range`/`Accept-Ranges`
  support — i.e. **progressive MP4 already works** through it
  (`local_hls_proxy.dart:203-215`);
- performs uzmovi per-segment RC4 signing (`local_hls_proxy.dart:397-423`).

Today it binds to `127.0.0.1` (`local_hls_proxy.dart:61`) and returns
`http://127.0.0.1:$_port/...` (`local_hls_proxy.dart:47`), so a Chromecast on the
LAN can't reach it. Exposing it on the LAN (with a token) turns almost every
"not castable" source into "castable", because the auth stays on the phone.

## Coverage matrix (with cast-through-proxy + Default Media Receiver)

| Source class | Naive cast | Cast-through-proxy (this plan) | Notes |
|---|---|---|---|
| Plain public HLS/MP4, no headers | ✅ | ✅ | Proxy is a transparent pass-through |
| `asilmedia` (Referer-gated) | ❌ | ✅ | Proxy injects `Referer` (`player_page.media.dart:5-12`) |
| Header/Referer/Cookie-gated (server, `cs:`, `an:`) | ❌ | ✅ | Proxy replays the resolved headers |
| Cloudflare-gated (`requiresCfBypass`, JS/`cs`/`an`) | ❌ | ✅ | Proxy uses the phone's `cf_clearance` + UA cookie jar |
| `animexin` / Dailymotion (IP-bound signed HLS, `useLocalProxy`) | ❌ | ✅ | Phone fetches all segments → IP binding satisfied |
| Progressive MP4 (headered) | ⚠️ | ✅ | Proxy range pass-through |
| `uzmovi` (`.mpd` DASH + per-segment RC4) | ❌ | ⚠️ **v2** | Proxy doesn't rewrite DASH manifests yet — see Limitations |
| Other DASH (`.mpd`) | ❌ | ⚠️ **v2** | Needs `.mpd` segment rewriting |
| HEVC/AV1-encoded streams | ❌ | ❌ (device) | Older Chromecasts can't decode; unavoidable, handle gracefully |

**v1 target:** all HLS (including headered / CF-gated / IP-bound / Referer-gated)
and progressive MP4 — the large majority of the catalog.
**v2:** DASH manifest rewriting (unlocks `uzmovi` and other `.mpd` sources).

## Scope / non-goals

- **Android only.** Google Cast has no official desktop sender SDK, so the
  Windows/`media_kit` build is out. iOS is a later phase (same proxy design +
  the iOS Cast SDK); note `cs:`/`an:` providers don't exist on iOS anyway.
- **Manga (`mn:`)** is excluded — image pages, not video.
- No custom Cast **receiver** app is needed (the proxy does header injection), so
  no Google Cast Developer Console registration for v1 — we use the Default
  Media Receiver app id `CC1AD845`.

---

## Component design

### 1. LAN-exposed proxy (`LocalHlsProxy` changes)

Add an opt-in "cast exposure" mode so normal in-app playback keeps using loopback
and only casting exposes the LAN surface.

- `Future<CastProxyInfo> enableCastExposure()`:
  - Start (or restart) the server bound to `InternetAddress.anyIPv4` (`0.0.0.0`)
    instead of loopback. Generate a random 32-byte base64url **session token**.
  - Resolve the phone's Wi-Fi IPv4 via `NetworkInterface.list()` (pick the
    non-loopback IPv4 on the `wlan`/`en` interface).
  - Return `{ lanIp, port, token }`.
- `Future<String> registerForCast({upstreamUrl, headers, localProxy, requestTransform})`:
  - Same as `register()` but returns a **LAN, token-scoped** URL:
    `http://<lanIp>:<port>/c/<token>/hls/<id><path><query>`.
  - Works for ANY source (headers may be empty) — so direct URLs are wrapped too.
- Token enforcement in `_handle`: require the `/c/<token>/…` prefix and match the
  active token; reject others `403`. Strip the `/c/<token>` prefix before the
  existing `/hls/<id>/…` match.
- Manifest rewrite base becomes `/c/<token>/hls/<sid>` so the token propagates to
  every rewritten segment/key URL automatically (reuses `_rewriteM3u8`).
- Add **CORS** + cast-friendly response headers on cast responses:
  `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Headers: *`, and answer
  `OPTIONS` preflight — the CAF receiver needs CORS for side-loaded tracks and
  some HLS cases.
- `Future<void> disableCastExposure()`: drop the token, evict cast sessions, and
  rebind to loopback (or stop) when the cast session ends.
- **Subtitles:** proxy the active subtitle file the same way (generic
  pass-through already handles non-manifest bodies) and hand the receiver a LAN
  VTT URL as a Cast text track. Convert SRT→VTT on the phone if needed.

> Security: bind to LAN **only while a cast session is active**; token lives in
> the URL path (not a header) because the receiver's own segment fetches won't
> carry custom headers; regenerate the token per session; never log it.

### 2. Cast sender — native Android module (MethodChannel)

Mirror the existing native-channel pattern (e.g. `soplay/cloudstream`) rather
than adding a heavyweight plugin — the app is already Kotlin-heavy and this keeps
full control.

- Add dependency `com.google.android.gms:play-services-cast-framework`.
- Add a `SozoCastOptionsProvider : OptionsProvider` returning `CastOptions` with
  `setReceiverApplicationId("CC1AD845")` (Default Media Receiver).
- Register it in `AndroidManifest.xml`:
  ```xml
  <meta-data
      android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
      android:value="com.soplay.sozo.cast.SozoCastOptionsProvider" />
  ```
- New `CastChannel.kt` (MethodChannel `soplay/cast`) exposing:
  - `isAvailable` — Cast + Play Services present.
  - `showDevicePicker` — launch the SDK's `MediaRouteChooserDialog` (reuse the
    SDK's discovery/picker UI; no custom discovery needed).
  - `loadMedia(url, contentType, title, poster, positionMs, isLive, subtitles[])`
    — build `MediaInfo` + `MediaLoadRequestData` and call
    `RemoteMediaClient.load(...)`.
  - `play` / `pause` / `seek(ms)` / `setVolume(v)` / `stop`.
  - EventChannel (or method callbacks) streaming session state
    (`connecting/connected/ended`), player state, position, and load errors.
- `contentType`: `application/x-mpegURL` for HLS, `video/mp4` for progressive.
- On `LOAD_FAILED`/`ERROR` from the receiver (codec unsupported, etc.), surface a
  typed error so Flutter can show "TV couldn't play this — try another quality or
  play on phone."

### 3. Flutter integration (`CastController` + player wiring)

- New `lib/core/cast/cast_controller.dart`: a thin Dart wrapper over the
  `soplay/cast` channel exposing `ValueNotifier<CastState>` (idle / connecting /
  connected + remote player value: position, duration, isPlaying, isBuffering,
  error). Shape it to overlap the parts of `PlayerController` the UI already uses
  so control code can branch cleanly.
- In `_PlayerPageState`, add `_castController` + `_isCasting`. When a cast session
  connects:
  1. capture the local position, `await _controller.pause()`,
  2. `enableCastExposure()` on the proxy, `registerForCast(...)` the **current
     source** (+ active subtitle), build the LAN URL,
  3. `castController.loadMedia(...)` with the captured position,
  4. set `_isCasting = true` and swap the video layer for a "Casting to <device>"
     poster panel with remote transport controls.
- Route existing control intents to the remote when casting: `_togglePlay`,
  `_seekTo`, `_seekRelative`, `_setPlayerVolume`, `_setSpeed`, quality/episode
  switches (re-register the new source through the proxy and re-`loadMedia`).
- On disconnect / player exit: `castController.stop()`, `disableCastExposure()`,
  optionally resume local playback at the remote's last position.
- Guard: only offer Cast when `!isDesktopPlatform && Platform.isAndroid`.

### 4. UI

- Add a Cast `_IconButton` to the top control row in
  `player_page.controls.dart` (the `Row` at `_buildControlsOverlay`, alongside
  orientation/lock/PiP/settings ~`player_page.controls.dart:690-728`). Show it
  only when `CastController.isAvailable` and at least one route is found; tint it
  when connected. Tap → `showDevicePicker`.
- Casting panel replacing `_buildVideoLayer` while `_isCasting`: poster/thumbnail,
  device name, buffering/error state, and the transport cluster reusing existing
  `_CenterIconButton`/slider widgets bound to the remote state.
- Add translation keys (`player.cast`, `player.casting_to`, `player.cast_failed`,
  `player.cast_unsupported_format`) to `assets/translations/{en,uz,ru}.json`.

---

## Android specifics / prerequisites

- **minSdk:** Cast framework requires `minSdk ≥ 21` (recent versions ≥ 23).
  Confirm `flutter.minSdkVersion` meets this; bump in `build.gradle.kts` if not.
- **Play Services:** already present (Firebase + `com.google.gms.google-services`
  in `android/app/build.gradle.kts`), which Cast needs.
- **Cleartext:** `usesCleartextTraffic="true"` is already set — required for the
  `http://` LAN proxy URL.
- **Minify:** release build has `isMinifyEnabled = false`
  (`build.gradle.kts:72`), so Cast SDK proguard/consumer rules are a non-issue
  for now (revisit if minify is re-enabled).
- **Theme:** `MediaRouteChooserDialog` needs an AppCompat/Theme.MaterialComponents
  context; if the launcher/Flutter theme isn't compatible, host the picker via a
  tiny transparent AppCompat activity or apply a Cast-compatible dialog theme.
- **Permissions:** `INTERNET` + `ACCESS_NETWORK_STATE` already declared; Cast
  discovery also benefits from `ACCESS_WIFI_STATE` / `CHANGE_WIFI_MULTICAST_STATE`
  (add if discovery is flaky on some routers).

---

## Implementation phases

### Phase 0 — Spike (½ day)
Measure real coverage: instrument `resolveMedia` results across the top live
providers and count how many are HLS vs DASH, headered vs plain, CF vs not. This
confirms v1 (HLS+MP4) coverage before building.

### Phase 1 — LAN proxy exposure
`enableCastExposure` / `registerForCast` / token gating / CORS / LAN IP discovery
/ subtitle proxying. Unit-test token enforcement and manifest rewrite with the
`/c/<token>` base. No UI yet — verify with `curl` from another LAN device.

### Phase 2 — Native Cast module
Dependency, `SozoCastOptionsProvider`, manifest meta-data, `CastChannel.kt`
(availability, device picker, load, transport, state events).

### Phase 3 — Flutter CastController + player wiring
`CastController`, `_isCasting` state machine, control routing, casting panel,
Cast button, translations.

### Phase 4 — Quality/episode/subtitle switching while casting
Re-register through the proxy and re-load on source change; side-load subtitle
tracks; graceful codec-error handling.

### Phase 5 (v2) — DASH support
Add `.mpd` manifest rewriting to the proxy (rewrite `SegmentTemplate`/`BaseURL`/
segment URLs back through the token base). Unlocks `uzmovi` and other DASH
sources. Verify the Default Media Receiver plays proxied DASH, else evaluate a
minimal styled receiver.

---

## Files to add / modify

### Add
```text
lib/core/cast/cast_controller.dart
lib/core/cast/cast_state.dart
android/app/src/main/kotlin/com/soplay/sozo/cast/CastChannel.kt
android/app/src/main/kotlin/com/soplay/sozo/cast/SozoCastOptionsProvider.kt
```

### Modify
```text
lib/core/player/local_hls_proxy.dart        # LAN exposure + token + CORS + registerForCast
lib/features/detail/presentation/pages/player_page.dart          # _castController, _isCasting state
lib/features/detail/presentation/pages/player_page.controls.dart # Cast button + casting panel
lib/features/detail/presentation/pages/player_page.media.dart    # route source through cast on connect
lib/core/di/injection.dart                  # register CastController
android/app/src/main/kotlin/com/soplay/sozo/MainActivity.kt      # register soplay/cast channel
android/app/src/main/AndroidManifest.xml    # OPTIONS_PROVIDER meta-data (+ wifi perms if needed)
android/app/build.gradle.kts                # play-services-cast-framework (+ minSdk check)
assets/translations/en.json | uz.json | ru.json
```

---

## Limitations (be honest in the UI)

- **Codec:** HEVC/AV1 streams fail on older Chromecasts regardless of the proxy —
  show a clear "TV can't play this format" message with a "play on phone" option.
- **DASH is v2:** `uzmovi` and other `.mpd` sources won't cast until Phase 5.
- **Desktop:** no cast (no sender SDK).
- **Same-LAN requirement:** phone and Chromecast must share the Wi-Fi; guest
  networks / AP isolation will block it.
- **Battery/heat:** the phone stays in the media path (it proxies every segment),
  so long casts keep the phone busy — keep the wakelock and warn on low battery.

## Testing checklist

- [ ] `curl http://<lanIp>:<port>/c/<token>/hls/<sid>/master.m3u8` from another
      LAN device returns a rewritten manifest; wrong/absent token → 403.
- [ ] Plain HLS casts and plays.
- [ ] `asilmedia` (Referer) casts and plays.
- [ ] A Cloudflare-gated source casts (proxy replays clearance).
- [ ] `animexin`/Dailymotion IP-bound HLS casts.
- [ ] Progressive MP4 casts with seek (range) working.
- [ ] Play/pause/seek/volume from the phone control the TV.
- [ ] Quality + episode switch re-loads on the TV.
- [ ] Subtitle track appears on the TV.
- [ ] Codec-unsupported source shows the graceful error, not a spinner.
- [ ] Ending the session / leaving the player rebinds the proxy to loopback and
      drops the token.
- [ ] Normal (non-cast) in-app playback still uses loopback and is unaffected.
```
