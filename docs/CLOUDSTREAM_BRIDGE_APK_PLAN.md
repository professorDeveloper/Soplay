# Sozo CloudBridge APK Plan for iOS CloudStream Support

## Goal

Enable CloudStream providers for the iOS version of Sozo without trying to run
`.cs3` plugins inside iOS.

CloudStream `.cs3` plugins are Android DEX bytecode. They require Android APIs,
`DexClassLoader`, CloudStream runtime classes, and often a real Android WebView.
iOS cannot load those plugins directly, and App Store rules do not allow an app
to download and execute external code that changes app functionality.

The proposed solution is a separate Android helper app:

**Sozo CloudBridge**

CloudBridge runs CloudStream plugins on Android and exposes a small HTTP API.
Sozo iOS connects to that API and uses the results as if they came from a normal
provider.

This keeps:

- Android code running on Android, where `.cs3` works.
- iOS app simple and App-Store safer.
- JSON shapes compatible with existing Sozo models.
- Current Android Sozo behavior unchanged.

---

## One-Sentence Architecture

Sozo iOS becomes a CloudStream client, while a separate Android APK becomes the
CloudStream execution host.

```text
Sozo iOS
  HTTPS/HTTP + token
  -> Sozo CloudBridge APK on Android
       -> CloudStream .cs3 plugins
       -> CloudStream provider APIs
       -> Sozo-compatible JSON
  <- provider/home/search/detail/loadLinks data
```

---

## Why This Is Needed

### Why iOS Cannot Run `.cs3`

CloudStream plugins are compiled Android/Kotlin artifacts. They are loaded by
Android with `DexClassLoader` or `PathClassLoader`.

iOS does not provide:

- Dalvik/ART runtime.
- Android framework classes.
- Android WebView APIs used by many CloudStream providers.
- Dynamic DEX loading.

Even if a JVM-like runtime were embedded, `.cs3` files are not plain JVM jars.
They depend on Android-specific runtime behavior.

### Why Windows Is Not the Best First Target

A Windows app cannot directly run `.cs3` either. It would still need an Android
runtime such as an emulator, WSA, Redroid, or a VM. That adds complexity and
makes the system less portable.

An Android APK is the cleanest execution host because CloudStream already works
there.

### App Store Safety

The iOS app should not download and execute CloudStream plugin code. It should
only call a user-configured bridge server and receive data.

The bridge is an external service, similar to using a backend API. The iOS app
contains fixed client logic and does not execute plugin code itself.

---

## Proposed Product: Sozo CloudBridge

CloudBridge is a separate Flutter project with Android native Kotlin code.

Suggested project name:

```text
sozo_cloudbridge
```

Suggested Android package:

```text
com.soplay.cloudbridge
```

CloudBridge can run in two modes:

1. **Personal Device Mode**
   - User installs CloudBridge APK on an Android phone.
   - Sozo iOS connects to that Android phone on the same Wi-Fi network.
   - Best for personal use and testing.

2. **Hosted Android Runtime Mode**
   - CloudBridge runs in Redroid or a real Android VM.
   - Sozo iOS connects to a public HTTPS endpoint.
   - Best for production-like use.

The APK should be designed so both modes use the same HTTP API.

---

## Current Sozo Behavior

### Android Sozo Today

Android Sozo already supports CloudStream natively:

- `CloudStreamChannel` uses `MethodChannel('soplay/cloudstream')`.
- `MainActivity.kt` registers the native channel.
- `RepoManager.kt` downloads CloudStream repos and `.cs3` files.
- `PluginHost.kt` loads providers and maps CloudStream responses into Sozo JSON.
- Provider IDs are namespaced as `cs:<providerName>`.

### iOS Sozo Today

Current `CloudStreamChannel.isSupported` returns false on iOS.

That means:

- CloudStream providers are not appended to the provider list.
- CloudStream source management is hidden or unavailable.
- Calls like `ensureLoaded`, `listProviders`, `search`, `load`, and `loadLinks`
  return empty/no-op data.

The new plan changes iOS from "CloudStream unsupported" to "CloudStream via
configured bridge".

---

## Target iOS User Experience

### Profile Screen

In Sozo iOS, the Profile screen should show a CloudStream entry:

```text
CloudStream Bridge
Not connected
```

or:

```text
CloudStream Bridge
Connected to 192.168.1.50:8787
```

This entry should appear near provider settings or in a dedicated integration
section.

### When User Taps "CloudStream Bridge"

If no bridge is configured, show a setup screen:

```text
CloudStream Bridge

CloudStream plugins cannot run directly on iOS. Connect Sozo to a Sozo
CloudBridge APK running on an Android device or hosted Android runtime.

[Scan QR Code]
[Enter Bridge URL]
[Learn How To Set Up]
```

Actions:

- **Scan QR Code**
  - Opens camera/QR scanner if available.
  - Reads bridge URL + token from the Android CloudBridge app.

- **Enter Bridge URL**
  - User enters:

    ```text
    http://192.168.1.50:8787
    ```

  - User enters token or pastes full URL with token.

- **Learn How To Set Up**
  - Opens a local help page explaining:
    - Install CloudBridge APK on Android.
    - Add CloudStream repos inside CloudBridge.
    - Keep Android device and iPhone on same Wi-Fi.
    - Copy or scan bridge URL.

### After URL Is Entered

Sozo iOS calls:

```http
GET /health
Authorization: Bearer <token>
```

If valid:

```text
Connected
CloudBridge v1.0.0
4 repos installed
32 providers available

[Use CloudStream Providers]
[Manage Connection]
[Disconnect]
```

If invalid:

```text
Could not connect to CloudBridge.

Check that:
- CloudBridge is running.
- Both devices are on the same Wi-Fi.
- The URL and token are correct.
```

### Provider Picker

When bridge is connected, Sozo iOS provider picker should include a new group:

```text
CloudStream
```

Provider IDs should still use the current namespace:

```text
cs:<providerName>
```

Examples:

```text
cs:SuperStream
cs:AnimeProvider
cs:MoviesHub
```

When the user selects a CloudStream provider on iOS:

- Save `cs:<providerName>` as current provider in Hive.
- Home/search/detail calls route to `CloudBridgeClient`.
- Existing UI remains the same.

### CloudStream Source Management on iOS

There are two possible UX choices.

Recommended MVP:

- Source repo management happens only in CloudBridge APK.
- Sozo iOS only connects and lists available providers.

Later enhancement:

- Sozo iOS can remotely add/remove repos by calling CloudBridge endpoints.
- This is convenient, but it should be protected by token auth.

For MVP, keep iOS simple:

```text
Manage repos in the CloudBridge Android app.
```

---

## CloudBridge Android APK UX

The Android CloudBridge app should have these screens.

### 1. Server Status

Shows:

```text
Sozo CloudBridge

Status: Running
Local URL: http://192.168.1.50:8787
Token: ••••••••••••

[Copy URL]
[Show QR]
[Regenerate Token]
[Stop Server]
```

The QR payload should include:

```json
{
  "type": "sozo-cloudbridge",
  "baseUrl": "http://192.168.1.50:8787",
  "token": "generated-token"
}
```

Or as a URL:

```text
sozo-cloudbridge://connect?baseUrl=http%3A%2F%2F192.168.1.50%3A8787&token=...
```

The JSON payload is easier for QR scanning.

### 2. Repositories

Allows:

- Add repo URL.
- List installed repos.
- Remove repo.
- Show install progress.

Supported inputs:

```text
https://example.com/repo.json
https://example.com/plugins.json
CloudStream shortcode, if implemented
```

The logic should reuse the existing `RepoManager.kt`.

### 3. Providers

Lists all available providers:

```text
Provider name
Repo name
Language / supported types
```

Actions:

- Test search.
- Test detail.
- Test links.

### 4. Logs

Show runtime logs:

- Repo install errors.
- Plugin load errors.
- Provider call errors.
- `loadLinks` source count.

This is important because CloudStream providers can break when target websites
change.

---

## CloudBridge HTTP API

All endpoints require authentication.

Recommended auth:

```http
Authorization: Bearer <token>
```

Fallback for QR/debug only:

```text
?token=<token>
```

Header auth should be preferred.

### `GET /health`

Checks bridge availability.

Response:

```json
{
  "ok": true,
  "name": "Sozo CloudBridge",
  "version": "1.0.0",
  "serverTime": "2026-06-09T12:00:00.000Z",
  "repoCount": 2,
  "providerCount": 18
}
```

### `GET /providers`

Returns CloudStream providers.

Response:

```json
{
  "items": [
    {
      "id": "cs:ProviderName",
      "name": "ProviderName",
      "icon": "https://example.com/icon.png",
      "repo": "Repo Name",
      "mode": "client",
      "category": "cloudstream",
      "description": "CloudStream"
    }
  ]
}
```

### `GET /repos`

Returns installed repos.

Response:

```json
{
  "items": [
    {
      "url": "https://example.com/repo.json",
      "name": "Example Repo",
      "providerCount": 12
    }
  ]
}
```

### `POST /repos`

Adds a repo.

Request:

```json
{
  "url": "https://example.com/repo.json"
}
```

Response:

```json
{
  "repo": "https://example.com/repo.json",
  "pluginCount": 30,
  "providers": ["ProviderA", "ProviderB"]
}
```

### `DELETE /repos`

Removes a repo.

Request:

```json
{
  "url": "https://example.com/repo.json"
}
```

Response:

```json
{
  "ok": true
}
```

### `GET /mainPage`

Gets provider home content.

Query:

```text
provider=ProviderName
page=1
```

Response shape must match Sozo `HomeDataModel`.

Example:

```json
{
  "provider": "cs:ProviderName",
  "banner": [],
  "sections": [
    {
      "label": "Popular",
      "items": [
        {
          "provider": "cs:ProviderName",
          "externalId": "...",
          "title": "Movie title",
          "slug": "...",
          "contentUrl": "https://...",
          "thumbnail": "https://...",
          "type": "movie"
        }
      ],
      "viewAll": {
        "type": "category",
        "slug": "cloudstream-section-data",
        "name": "Popular"
      }
    }
  ]
}
```

### `GET /section`

Gets paginated section items.

Query:

```text
provider=ProviderName
data=<CloudStream MainPageData.data>
page=1
```

Response shape must match `ViewAllPagingModel`.

```json
{
  "provider": "cs:ProviderName",
  "items": [],
  "page": 1,
  "totalPages": 2
}
```

### `GET /search`

Searches provider.

Query:

```text
provider=ProviderName
q=naruto
page=1
```

Response shape must match `SearchModel`.

```json
{
  "provider": "cs:ProviderName",
  "items": [],
  "query": "naruto",
  "page": 1,
  "totalPages": 1
}
```

### `GET /load`

Loads detail and episodes.

Query:

```text
provider=ProviderName
url=<contentUrl>
```

Response should match `DetailModel` and `PlaybackModel` compatible fields.

```json
{
  "provider": "cs:ProviderName",
  "contentId": "https://...",
  "contentUrl": "https://...",
  "title": "Title",
  "description": "Description",
  "thumbnail": "https://...",
  "banner": "https://...",
  "year": 2025,
  "duration": "120 min",
  "genres": ["Action"],
  "type": "Movie",
  "isSerial": false,
  "cast": [],
  "related": [],
  "episodes": [
    {
      "episode": 1,
      "label": "Play",
      "mediaRef": "cloudstream-data-url"
    }
  ]
}
```

### `GET /loadLinks`

Resolves playable links.

Query:

```text
provider=ProviderName
data=<episode.mediaRef>
```

Response shape must match `MediaResolveModel`.

```json
{
  "videoUrl": "https://...",
  "type": "hls",
  "headers": {
    "Referer": "https://..."
  },
  "videoSources": [
    {
      "quality": "Host · 1080p",
      "videoUrl": "https://...",
      "type": "hls",
      "host": "Host",
      "isDefault": true,
      "accessible": true,
      "headers": {
        "Referer": "https://..."
      }
    }
  ],
  "subtitles": [
    {
      "label": "English",
      "file": "https://...",
      "default": false
    }
  ]
}
```

---

## Reusing Existing Android Code

The current Sozo Android project already contains most of the needed native
logic.

Files to reuse or copy into CloudBridge:

```text
android/app/src/main/kotlin/com/soplay/sozo/cloudstream/PluginHost.kt
android/app/src/main/kotlin/com/soplay/sozo/cloudstream/RepoManager.kt
android/app/src/main/kotlin/com/lagradost/cloudstream3/plugins/Plugin.kt
android/app/src/main/kotlin/com/lagradost/cloudstream3/network/CloudflareKiller.kt
```

CloudBridge also needs the CloudStream runtime dependency:

```kotlin
implementation("com.github.recloudstream.cloudstream:library:v4.7.0")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
compileOnly("com.squareup.okhttp3:okhttp:4.12.0")
```

Also keep the packaging exclusions already used in Sozo Android:

```kotlin
packaging {
    resources {
        excludes += setOf(
            "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
            "META-INF/DEPENDENCIES",
            "META-INF/INDEX.LIST",
            "META-INF/LICENSE",
            "META-INF/LICENSE.txt",
            "META-INF/LICENSE.md",
            "META-INF/NOTICE",
            "META-INF/NOTICE.txt",
            "META-INF/NOTICE.md",
            "META-INF/{AL2.0,LGPL2.1}",
        )
    }
}
```

---

## HTTP Server Implementation Options

### Recommended MVP: NanoHTTPD

Pros:

- Small.
- Simple.
- Easy to embed in Android app.
- Enough for JSON endpoints.

Example dependency:

```kotlin
implementation("org.nanohttpd:nanohttpd:2.3.1")
```

### Alternative: Ktor Embedded Server

Pros:

- Cleaner routing.
- Better middleware structure.

Cons:

- Larger dependency.
- More setup for Android.

Recommendation:

Use NanoHTTPD for MVP, then upgrade only if needed.

---

## CloudBridge Native Server Sketch

Native Kotlin structure:

```text
com.soplay.cloudbridge
  MainActivity.kt
  bridge/
    BridgeServer.kt
    BridgeAuth.kt
    BridgeSettings.kt
  cloudstream/
    PluginHost.kt
    RepoManager.kt
```

`BridgeServer.kt` responsibilities:

- Start HTTP server on `0.0.0.0:8787` or configurable port.
- Validate token.
- Parse query/body.
- Call `RepoManager` and `PluginHost`.
- Return JSON.
- Log request duration and errors.

Important:

- Bind to `0.0.0.0` for LAN access.
- Show local Wi-Fi IP in UI.
- Do not expose without token.

---

## CloudBridge Flutter UI

The Flutter side of CloudBridge can be simple.

Suggested screens:

```text
lib/
  main.dart
  app.dart
  bridge/
    bridge_channel.dart
    bridge_state.dart
  pages/
    server_status_page.dart
    repos_page.dart
    providers_page.dart
    logs_page.dart
```

Flutter talks to native Kotlin with a MethodChannel:

```text
sozo/cloudbridge
```

Methods:

```text
startServer
stopServer
serverStatus
setPort
regenerateToken
addRepo
removeRepo
listRepos
listProviders
testSearch
getLogs
clearLogs
```

The HTTP API is for Sozo iOS. The MethodChannel is only for the CloudBridge UI.

---

## Sozo iOS Integration

### New Dart Client

Add:

```text
lib/core/cloudstream/cloudbridge_client.dart
```

Responsibilities:

- Store/load bridge settings.
- Check health.
- Call CloudBridge endpoints.
- Convert response to the same dynamic maps/lists returned by
  `CloudStreamChannel`.

Example interface:

```dart
class CloudBridgeClient {
  CloudBridgeClient({
    required Dio dio,
    required HiveService hive,
  });

  Future<bool> isConfigured();
  Future<CloudBridgeHealth?> health();
  Future<List<dynamic>> listProviders();
  Future<Map<String, dynamic>> getMainPage(String provider, {int page = 1});
  Future<List<dynamic>> getGenres(String provider);
  Future<Map<String, dynamic>> getSection(String provider, String data, {int page = 1});
  Future<Map<String, dynamic>> search(String provider, String query);
  Future<Map<String, dynamic>> load(String provider, String url);
  Future<Map<String, dynamic>> loadLinks(String provider, String data);
}
```

### Modify `CloudStreamChannel`

Current file:

```text
lib/core/cloudstream/cloudstream_channel.dart
```

Change iOS behavior:

- Android still uses MethodChannel.
- iOS uses `CloudBridgeClient` if configured.
- If no bridge is configured, return empty data.

Concept:

```dart
static bool get isSupported =>
    Platform.isAndroid || CloudBridgeSettings.isConfigured;
```

But because this is async, prefer:

```dart
static bool get isNativeSupported => Platform.isAndroid;
static bool get canUseBridge => Platform.isIOS;
```

Then provider loading should call an async helper:

```dart
final providers = await CloudStreamChannel.ensureLoaded();
```

On iOS, `ensureLoaded()` should:

1. Read bridge settings.
2. Call `/health`.
3. Call `/providers`.
4. Return provider list.

### Store Bridge Settings

Add Hive keys:

```dart
static const String cloudBridgeBaseUrlKey = 'cloud_bridge_base_url';
static const String cloudBridgeTokenKey = 'cloud_bridge_token';
static const String cloudBridgeEnabledKey = 'cloud_bridge_enabled';
```

Add `HiveService` methods:

```dart
String getCloudBridgeBaseUrl();
String getCloudBridgeToken();
bool get isCloudBridgeEnabled;
Future<void> saveCloudBridge({
  required String baseUrl,
  required String token,
});
Future<void> setCloudBridgeEnabled(bool value);
Future<void> clearCloudBridge();
```

### ProviderBloc Behavior

Current:

```dart
await _appendCloudStreamProviders(providers);
```

New behavior:

- Android: native `CloudStreamChannel.ensureLoaded()`.
- iOS: bridge `CloudStreamChannel.ensureLoaded()`.
- If not configured, do not append CloudStream providers.

If configured but unreachable:

- Keep normal backend providers.
- Show a warning inside CloudStream Bridge settings screen.
- Do not break app startup.

### Profile UI Additions

In `profile_page.dart`, add a CloudBridge tile on iOS.

Suggested copy:

```text
CloudStream Bridge
Connect to an Android CloudBridge host
```

States:

```text
Not configured
Connected
Offline
Token invalid
```

Tile action opens:

```text
/cloudstream-bridge
```

Add route:

```text
lib/features/cloudstream/presentation/pages/cloudbridge_settings_page.dart
```

Route:

```dart
GoRoute(
  path: '/cloudstream-bridge',
  builder: (context, state) => const CloudBridgeSettingsPage(),
)
```

### CloudBridge Settings Page in Sozo

Fields:

- Bridge URL.
- Token.
- Enable switch.

Actions:

- Test Connection.
- Save.
- Disconnect.
- Refresh Providers.

After successful save:

- Call `ProviderBloc.add(ProviderLoad())`.
- Provider sheet will include CloudStream group.

---

## Runtime Flow on iOS

### Connect Flow

```text
User opens Profile
User taps CloudStream Bridge
User enters URL/token or scans QR
Sozo calls /health
If OK, saves settings
Sozo reloads ProviderBloc
ProviderBloc appends cs:* providers from /providers
User selects a cs:* provider
Home/Search/Detail now route through CloudBridge
```

### Home Flow

```text
Current provider = cs:ProviderName
HomeRepository.loadHome()
CloudStreamChannel.getMainPage("ProviderName")
iOS CloudBridgeClient GET /mainPage?provider=ProviderName
CloudBridge calls PluginHost.getMainPageJson()
Sozo receives HomeDataModel-compatible JSON
Home UI renders normally
```

### Detail Flow

```text
User opens title
DetailRepository.getDetail()
CloudBridgeClient GET /load
Response contains detail + episodes
Detail UI renders normally
```

### Playback Flow

```text
User taps Play
Player/Detail asks resolveMedia
CloudBridgeClient GET /loadLinks
Bridge runs CloudStream loadLinks()
Response contains videoSources/subtitles/headers
Sozo Player opens source using video_player
```

Important:

- If returned URLs are public direct/HLS URLs, iOS can play them.
- If provider requires Android-only WebView interaction at playback time,
  CloudBridge must resolve final links before returning.
- If links are IP-bound to the Android device, iOS playback may fail. For those,
  CloudBridge may need a remote HLS proxy endpoint.

---

## IP-Bound Stream Problem

Some hosts bind signed video URLs to the IP that resolved them.

Example issue:

```text
CloudBridge Android resolves video link from Android IP.
iPhone tries to play the URL from iPhone IP.
CDN rejects with 403.
```

For local Wi-Fi this may still work if both devices share the same public NAT IP,
but it can fail with:

- Mobile networks.
- VPNs.
- IPv4/IPv6 mismatch.
- Strict host sessions.

### Solution: Bridge HLS Proxy

CloudBridge should optionally proxy playback:

```text
Sozo iOS player
  -> http://android-ip:8787/proxy/hls/<session>/master.m3u8
CloudBridge
  -> upstream CDN with Android cookies/headers
```

This is similar to current Sozo `LocalHlsProxy`, but it runs inside CloudBridge
and is reachable from iOS.

Add to `loadLinks` source:

```json
{
  "quality": "Host · 1080p",
  "videoUrl": "http://192.168.1.50:8787/proxy/hls/abc/master.m3u8",
  "type": "hls",
  "headers": {
    "Authorization": "Bearer token"
  },
  "proxiedByBridge": true
}
```

MVP can skip this, but production should add it for reliability.

---

## Security Requirements

CloudBridge is a local HTTP server. It must not be open without protection.

Minimum requirements:

- Random token generated on first launch.
- Token required for every API request.
- Ability to regenerate token.
- Show warning when server is running on public network.
- Do not log token in plain text.
- CORS can be disabled or restricted because Sozo mobile client does not need
  browser CORS.

Recommended token length:

```text
32 random bytes, base64url encoded
```

Recommended headers:

```http
Authorization: Bearer <token>
```

Optional:

- Rate limit failed auth attempts.
- Allow-list client IPs.
- HTTPS for hosted mode.

---

## Hosted Mode

For production or TestFlight demos, CloudBridge can run in hosted Android.

Options:

1. Redroid in Docker on a KVM VPS.
2. Real Android device connected to server network.
3. Android emulator on a persistent VM.

Hosted mode should use:

- HTTPS reverse proxy.
- Token auth.
- Redis/cache at backend layer if many users.
- Multiple bridge instances if load grows.

Recommended hosted URL shape:

```text
https://cloudbridge.sozo.example
```

Sozo iOS does not care whether the bridge is local or hosted. It only needs
base URL + token.

---

## Implementation Phases

### Phase 1: CloudBridge APK MVP

Create separate Flutter project:

```text
sozo_cloudbridge
```

Implement:

- Android native `PluginHost.kt`.
- Android native `RepoManager.kt`.
- NanoHTTPD server.
- Token auth.
- `/health`.
- `/providers`.
- `/repos`.
- `/mainPage`.
- `/section`.
- `/search`.
- `/load`.
- `/loadLinks`.
- Simple Flutter UI for status/repos/providers/logs.

Do not change Sozo iOS yet.

Acceptance:

```bash
curl -H "Authorization: Bearer TOKEN" http://ANDROID_IP:8787/health
curl -H "Authorization: Bearer TOKEN" http://ANDROID_IP:8787/providers
```

### Phase 2: Sozo iOS Bridge Settings

In current Sozo project:

- Add bridge settings Hive keys.
- Add `CloudBridgeClient`.
- Add iOS CloudBridge settings page.
- Add profile tile.
- Add route.
- Add connection test.

Acceptance:

- User can save bridge URL/token.
- Connection status shows OK.
- ProviderBloc can reload providers.

### Phase 3: Provider Routing on iOS

Modify:

```text
lib/core/cloudstream/cloudstream_channel.dart
lib/features/profile/presentation/bloc/provider_bloc.dart
lib/features/home/data/repositories/home_repository_imp.dart
lib/features/search/data/repositories/search_repository_imp.dart
lib/features/detail/data/repositories/detail_repository_impl.dart
```

Most repositories already call `CloudStreamChannel` for `cs:` providers, so the
main work is making `CloudStreamChannel` return bridge data on iOS.

Acceptance:

- iOS provider sheet shows CloudStream group after bridge connection.
- Selecting a `cs:` provider loads home.
- Search works.
- Detail works.

### Phase 4: Playback

Test `loadLinks` sources on iOS player.

Acceptance:

- HLS direct source plays.
- MP4 direct source plays.
- Subtitles appear when returned.
- Headers are passed correctly.

If many streams fail with 403, implement bridge proxy.

### Phase 5: Bridge Playback Proxy

Add:

```text
GET /proxy/hls/<session>/<path>
GET /proxy/file/<session>
```

Bridge should:

- Fetch upstream with Android-side headers/cookies.
- Rewrite HLS playlists.
- Stream segments.
- Expire sessions.

Acceptance:

- IP-bound HLS plays through bridge.
- Segment URLs do not leak token in logs.
- Sessions expire automatically.

---

## Files to Add or Modify in Sozo

### Add

```text
lib/core/cloudstream/cloudbridge_client.dart
lib/core/cloudstream/cloudbridge_settings.dart
lib/features/cloudstream/presentation/pages/cloudbridge_settings_page.dart
```

### Modify

```text
lib/core/constants/app_constants.dart
lib/core/storage/hive_service.dart
lib/core/cloudstream/cloudstream_channel.dart
lib/core/di/injection.dart
lib/core/router/app_router.dart
lib/features/profile/presentation/pages/profile_page.dart
lib/features/profile/presentation/bloc/provider_bloc.dart
```

Optional later:

```text
assets/translations/en.json
assets/translations/uz.json
assets/translations/ru.json
```

---

## Files to Create in CloudBridge Project

```text
sozo_cloudbridge/
  pubspec.yaml
  lib/
    main.dart
    app.dart
    pages/
      server_status_page.dart
      repos_page.dart
      providers_page.dart
      logs_page.dart
    bridge/
      bridge_channel.dart
      bridge_models.dart
  android/app/src/main/kotlin/com/soplay/cloudbridge/
    MainActivity.kt
    bridge/
      BridgeServer.kt
      BridgeSettings.kt
      BridgeLogger.kt
    cloudstream/
      PluginHost.kt
      RepoManager.kt
  android/app/src/main/kotlin/com/lagradost/cloudstream3/
    plugins/Plugin.kt
    network/CloudflareKiller.kt
```

---

## Testing Checklist

### CloudBridge APK

- [ ] App starts.
- [ ] Server starts.
- [ ] Local IP and port are shown.
- [ ] Token is generated.
- [ ] `/health` rejects missing token.
- [ ] `/health` accepts valid token.
- [ ] Repo URL can be added.
- [ ] Plugin install progress is visible.
- [ ] Providers list appears.
- [ ] `/providers` returns `cs:` providers.
- [ ] `/search` returns items.
- [ ] `/load` returns detail and episodes.
- [ ] `/loadLinks` returns video sources.

### Sozo iOS

- [ ] CloudBridge settings page opens.
- [ ] Invalid URL shows useful error.
- [ ] Valid bridge saves settings.
- [ ] ProviderBloc reloads after save.
- [ ] CloudStream group appears in provider picker.
- [ ] Selecting provider saves `cs:<name>`.
- [ ] Home loads through bridge.
- [ ] Search loads through bridge.
- [ ] Detail loads through bridge.
- [ ] Playback starts from `loadLinks`.
- [ ] Disconnect removes CloudStream providers on next reload.

### Network

- [ ] Same Wi-Fi works.
- [ ] Android hotspot works.
- [ ] iPhone hotspot to Android works if supported.
- [ ] Hosted HTTPS bridge works.
- [ ] Offline bridge does not crash Sozo.

---

## Troubleshooting

### Sozo iOS Cannot Connect

Check:

- Android and iPhone are on same network.
- CloudBridge server is running.
- Correct IP address is used.
- Router allows device-to-device LAN traffic.
- Token is correct.
- Firewall/hotspot is not blocking port.

### Providers Do Not Appear

Check:

- `/providers` returns items.
- Provider IDs start with `cs:`.
- Sozo saved bridge settings.
- ProviderBloc was reloaded.
- CloudBridge has repos installed.

### Search Works but Playback Fails

Possible causes:

- Source URL is expired.
- Source URL is IP-bound to Android.
- Missing headers.
- Host blocks iOS user agent.

Fixes:

- Return exact headers from CloudStream `ExtractorLink`.
- Use bridge playback proxy.
- Refresh `loadLinks` immediately before playing.

### Some Plugins Fail to Load

Expected. Some CloudStream plugins depend on CloudStream app-module classes not
present in the library runtime. Add clean-room stubs only when needed.

---

## Recommended MVP Decision

Build CloudBridge as a separate Android APK first.

Do not start with Windows.
Do not try to run `.cs3` inside iOS.
Do not build hosted Redroid before the local APK proves the API.

MVP success means:

```text
Android CloudBridge APK runs provider plugins.
iOS Sozo connects to it.
iOS Sozo can browse and play at least one CloudStream provider.
```

After that, decide whether to:

- Add bridge playback proxy.
- Deploy hosted Redroid mode.
- Add remote repo management from iOS.
- Add QR pairing.

---

## Final Architecture Summary

```text
Current Android Sozo:
  Sozo Android -> native MethodChannel -> PluginHost -> CloudStream

New iOS Sozo:
  Sozo iOS -> CloudBridgeClient HTTP -> CloudBridge APK -> PluginHost -> CloudStream

CloudBridge APK:
  Android-only helper app that owns repos, plugins, provider calls, and optional
  playback proxy.
```

This is the safest and most practical way to make CloudStream available to iOS
users while preserving the existing Sozo architecture.
