# AnimeXin / Dailymotion — Mobile-side Local HLS Proxy (Variant 1)

`docs/dailymotion-403.md` da tasvirlangan 403 muammosini hal qilish uchun
**hybrid arxitektura** tanlandi:

- **Backend** (animexin-video v2 extractor) — `/embed` + `/player/metadata`
  ni mobil orqali (Runtime.http_get/json) chaqiradi. Imzolangan m3u8 URL
  qurilma IP'siga bog'lanadi. Har bir source `useLocalProxy: true` bilan
  qaytariladi.
- **Mobil** (Dart) — ichida HTTP server ko'taradi. ExoPlayer'ga shu serverning
  URL'i beriladi. Lokal server CDN bilan **bir xil Dio instance** (cookie jar
  + egress) orqali muloqot qiladi → barcha so'rovlar bir IP'dan ketadi →
  403 yo'q.

## Diagramma

```
┌──────────────┐   /metadata   ┌──────────────┐
│ Runtime.dart │ ────────────▶ │  Dailymotion │
│  (cookieJar) │ ◀──────────── │   metadata   │
└──────┬───────┘   m3u8+cookie └──────────────┘
       │
       ▼
┌──────────────┐
│ LocalHlsProxy│ ◀────── ExoPlayer (127.0.0.1:PORT/master.m3u8)
│  (HttpServer)│
└──────┬───────┘
       │ same Dio (cookieJar)
       ▼
┌──────────────┐
│ cdndirector  │ master.m3u8 → variant.m3u8 → .ts
│ vod3.dmcdn.. │   (IP-matched, cookies present → 200 OK)
└──────────────┘
```

## Extractor javobi shakli (v2)

`animexin-video.js` v2 har bir Dailymotion source uchun:

```json
{
  "quality":       "1080p",
  "videoUrl":      "https://cdndirector.dailymotion.com/cdn/manifest/video/<id>.m3u8?sec=...",
  "type":          "hls",
  "host":          "dailymotion",
  "isDefault":     true,
  "useLocalProxy": true,
  "headers": {
    "User-Agent": "Mozilla/5.0 (Linux; Android 13) ...",
    "Referer":    "https://www.dailymotion.com/",
    "Origin":     "https://www.dailymotion.com"
  }
}
```

Mobil tomon `useLocalProxy === true` bo'lsa, URL'ni to'g'ridan-to'g'ri
ExoPlayer'ga yubormaslik kerak — avval lokal proxy'ga ro'yxatga olib,
qaytarilgan lokal URL'ni player'ga berish.

## Dart implementatsiya — Reference

> Bu kod o'sha-o'sha ko'chirilishi shart emas. U skeletni ko'rsatadi.
> Sizning mavjud Dio/CookieJar inyeksiyangizga moslab oling.

### 1. `local_hls_proxy.dart`

```dart
// pubspec.yaml:
//   dio: ^5.5.0
//   dio_cookie_manager: ^3.1.1
//   cookie_jar: ^4.0.8

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';

class LocalHlsProxy {
  LocalHlsProxy(this._dio);

  final Dio _dio;
  HttpServer? _server;
  int? _port;
  final Map<String, _Session> _sessions = {};

  /// Pop-call: register an upstream HLS URL + headers and get back a
  /// localhost URL the player can load directly.
  Future<String> register({
    required String upstreamUrl,
    required Map<String, String> headers,
  }) async {
    await _ensureStarted();
    final id = _randomId();
    final parsed = Uri.parse(upstreamUrl);
    _sessions[id] = _Session(
      origin: '${parsed.scheme}://${parsed.authority}',
      basePath: parsed.path.substring(0, parsed.path.lastIndexOf('/')),
      cdnQuery: parsed.query,
      headers: headers,
      lastAccess: DateTime.now(),
    );
    return 'http://127.0.0.1:$_port/hls/$id${parsed.path}'
        '${parsed.hasQuery ? '?${parsed.query}' : ''}';
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    // OS picks a free port. 127.0.0.1 only — never expose to LAN.
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest req) async {
    final match = RegExp(r'^/hls/([a-f0-9]+)(/.*)$')
        .firstMatch(req.requestedUri.path);
    if (match == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final sid = match.group(1)!;
    var cdnPath = match.group(2)!;
    final sess = _sessions[sid];
    if (sess == null) {
      req.response.statusCode = 410;
      await req.response.close();
      return;
    }
    sess.lastAccess = DateTime.now();

    // /_h/<base64-host>/<path> — cross-origin segment routing
    var origin = sess.origin;
    final hMatch = RegExp(r'^/_h/([A-Za-z0-9_-]+)(/.*)$').firstMatch(cdnPath);
    if (hMatch != null) {
      origin = 'https://${_b64UrlDecode(hMatch.group(1)!)}';
      cdnPath = hMatch.group(2)!;
    }

    final resolved = cdnPath.startsWith(sess.basePath) || origin != sess.origin
        ? cdnPath
        : '${sess.basePath}$cdnPath';
    final qs = req.requestedUri.hasQuery
        ? '?${req.requestedUri.query}'
        : (sess.cdnQuery.isNotEmpty ? '?${sess.cdnQuery}' : '');
    final upstreamUrl = '$origin$resolved$qs';

    try {
      final resp = await _dio.get<List<int>>(
        upstreamUrl,
        options: Options(
          headers: sess.headers,
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (_) => true,
          // Important: don't let Dio decompress before we forward bytes.
          // (Dio handles gzip transparently; that's fine.)
        ),
      );
      final status = resp.statusCode ?? 502;
      if (status >= 400) {
        req.response.statusCode = status;
        await req.response.close();
        return;
      }

      final ct = (resp.headers.value('content-type') ?? '').toLowerCase();
      final isManifest =
          ct.contains('mpegurl') || resolved.endsWith('.m3u8') || resolved.endsWith('.mpd');
      if (isManifest) {
        // Advance basePath only for same-origin playlists.
        if (origin == sess.origin) {
          sess.basePath = resolved.substring(0, resolved.lastIndexOf('/'));
        }
        final text = String.fromCharCodes(resp.data!);
        final rewritten =
            _rewriteM3u8(text, '/hls/$sid', sess.origin, upstreamUrl);
        req.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        req.response.write(rewritten);
      } else {
        if (ct.isNotEmpty) {
          req.response.headers.set(HttpHeaders.contentTypeHeader, ct);
        }
        req.response.add(resp.data!);
      }
      await req.response.close();
    } catch (e) {
      req.response.statusCode = 502;
      req.response.write('Proxy error: $e');
      await req.response.close();
    }
  }

  String _rewriteM3u8(
      String content, String base, String sessionOrigin, String upstreamUrl) {
    final sessionHost = Uri.parse(sessionOrigin).host;
    String rewriteUrl(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return raw;
      Uri abs;
      try {
        abs = Uri.parse(t).isAbsolute
            ? Uri.parse(t)
            : Uri.parse(upstreamUrl).resolve(t);
      } catch (_) {
        return '$base/$t';
      }
      final qStr = abs.hasQuery ? '?${abs.query}' : '';
      if (abs.host == sessionHost) {
        return '$base${abs.path}$qStr';
      }
      final tag = _b64UrlEncode(abs.host);
      return '$base/_h/$tag${abs.path}$qStr';
    }

    final lines = content.split('\n');
    final out = <String>[];
    for (final l in lines) {
      final t = l.trim();
      if (t.isEmpty) {
        out.add(l);
        continue;
      }
      if (t.startsWith('#')) {
        // Rewrite URI="..." inside #EXT-X-KEY, #EXT-X-MEDIA, etc.
        out.add(l.replaceAllMapped(
          RegExp(r'URI="([^"]+)"'),
          (m) => 'URI="${rewriteUrl(m.group(1)!)}"',
        ));
        continue;
      }
      out.add(rewriteUrl(t));
    }
    return out.join('\n');
  }

  String _randomId() {
    // 12-byte hex
    final r = Random.secure();
    return List.generate(24, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
  }

  String _b64UrlEncode(String s) =>
      base64UrlEncode(utf8.encode(s)).replaceAll('=', '');
  String _b64UrlDecode(String s) =>
      utf8.decode(base64Url.decode(s + '=' * ((4 - s.length % 4) % 4)));

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _sessions.clear();
  }
}

class _Session {
  _Session({
    required this.origin,
    required this.basePath,
    required this.cdnQuery,
    required this.headers,
    required this.lastAccess,
  });
  final String origin;
  String basePath;
  final String cdnQuery;
  final Map<String, String> headers;
  DateTime lastAccess;
}
```

### 2. Player'ga ulanish

`PlayerPage` (yoki shunga o'xshash) ichida player ochilishidan oldin:

```dart
final proxy = LocalHlsProxy(ref.read(dioWithCookieJarProvider));

String resolvePlayableUrl(VideoSource src) {
  if (src.useLocalProxy == true && src.type == 'hls') {
    // Sync wrapper around proxy.register — use async init in your real code.
    return await proxy.register(
      upstreamUrl: src.videoUrl,
      headers: src.headers,
    );
  }
  return src.videoUrl;
}
```

`ExoPlayer`/`video_player` shu URL'ni oddiy HLS sifatida ochadi.

### 3. AndroidManifest.xml

`http://127.0.0.1:PORT` cleartext bo'lgani uchun:

```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

Yoki domain-specific (xavfsizroq):

```xml
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">127.0.0.1</domain>
  </domain-config>
</network-security-config>
```

### 4. iOS — Info.plist

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>127.0.0.1</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
    </dict>
  </dict>
</dict>
```

## SafeCookieManager

`docs/dailymotion-403.md` da aytilgan `SafeCookieManager` interceptor
**hali ham kerak** — `Dailymotion`'ning nostandart `Set-Cookie` qiymatlarini
to'g'ri parslamasdan butun javobni reject qilmasligi uchun. Lokal proxy
shu Dio orqali ishlaydi.

## Sinov ro'yxati

- [ ] `useLocalProxy: true` bo'lgan source ochilganda, `[PLAYER]` log
      `http://127.0.0.1:NNNN/hls/.../master.m3u8` ko'rsatadi
- [ ] `master.m3u8` 200 qaytaradi
- [ ] Variantlar 200 qaytaradi (cross-origin `_h/...` yo'li ham)
- [ ] `.ts` segmentlar 200 qaytaradi
- [ ] Player o'ynaydi, seek qiladi, oxirigacha buzilmaydi
- [ ] Bir nechta navbatma-navbat ochilgan epizodlarda eski session'lar
      eskirib yo'qoladi (SESSION_TTL ga e'tibor bering)

## Eslatma — backend ham hozir uchun ishlaydi

`hlsProxy.js` server-side proxy hali ham mavjud (vidrock, kelajak provayderlar
uchun foydali bo'lishi mumkin). animexin'ga ulanmagan — shu kifoya.
Agar mobil tomon lokal proxy yozish murakkab bo'lib qolsa, animexin
`resolveMedia`'sini server-side `hlsProxy.create(..., { fetcher: 'curl' })`
ga qaytarib ulash bir-ikki qator o'zgartirish.
