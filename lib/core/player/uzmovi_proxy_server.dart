import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:soplay/core/player/uzmovi_proxy_session.dart';

/// Local HTTP proxy that funnels ExoPlayer requests through an active
/// [UzmoviProxySession]. ExoPlayer sees a plain HLS URL on 127.0.0.1;
/// every request is forwarded through the WebView's signed fetch().
///
/// Singleton: only one server per app lifetime. Sessions live inside it.
class UzmoviProxyServer {
  UzmoviProxyServer._() {
    _sweeper = Timer.periodic(const Duration(minutes: 1), (_) => _sweepIdle());
  }
  static final UzmoviProxyServer instance = UzmoviProxyServer._();

  HttpServer? _server;
  int _port = 0;
  final Map<String, _Entry> _sessions = {};
  int _seq = 0;
  // ignore: unused_field
  Timer? _sweeper;   // kept alive by the class

  // No more than this many WebView sessions at once. Each one holds a
  // Chromium tab (~50-100MB). Older sessions are evicted FIFO when full.
  static const int _maxSessions = 2;
  // A session with no activity for this long is auto-disposed.
  static const Duration _idleTtl = Duration(minutes: 15);

  void _touch(_Entry e) {
    e.lastAccess = DateTime.now();
  }

  void _sweepIdle() {
    final now = DateTime.now();
    final stale = <String>[];
    _sessions.forEach((sid, e) {
      if (now.difference(e.lastAccess) > _idleTtl) stale.add(sid);
    });
    for (final sid in stale) {
      final e = _sessions.remove(sid);
      if (e != null) {
        if (kDebugMode) debugPrint('[UzProxy] sweep idle session=$sid');
        unawaited(e.session.dispose());
      }
    }
  }

  void _evictIfFull() {
    while (_sessions.length >= _maxSessions) {
      // Drop the oldest by lastAccess.
      MapEntry<String, _Entry>? oldest;
      _sessions.forEach((sid, e) {
        if (oldest == null || e.lastAccess.isBefore(oldest!.value.lastAccess)) {
          oldest = MapEntry(sid, e);
        }
      });
      if (oldest == null) break;
      _sessions.remove(oldest!.key);
      if (kDebugMode) debugPrint('[UzProxy] evict oldest session=${oldest!.key}');
      unawaited(oldest!.value.session.dispose());
    }
  }

  /// Boots the local server on a free port if not already running.
  /// Returns the base URL like `http://127.0.0.1:<port>`.
  Future<String> _ensureStarted() async {
    if (_server != null) return 'http://127.0.0.1:$_port';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = server.port;
    _server = server;
    server.listen(_handle);
    if (kDebugMode) debugPrint('[UzProxy] listening on 127.0.0.1:$_port');
    return 'http://127.0.0.1:$_port';
  }

  /// Registers a session and returns the local master playlist URL.
  /// The caller (player_page) MUST call [unregister] when playback ends.
  Future<String> register({
    required UzmoviProxySession session,
    required String upstreamMasterUrl,
  }) async {
    await _ensureStarted();
    _evictIfFull();
    final sid = (++_seq).toString();
    _sessions[sid] = _Entry(session: session, masterUrl: upstreamMasterUrl);
    if (kDebugMode) debugPrint('[UzProxy] register sid=$sid active=${_sessions.length}');
    return 'http://127.0.0.1:$_port/master/$sid/playlist.m3u8';
  }

  Future<void> unregister(String localUrl) async {
    final sid = _extractSid(localUrl);
    if (sid == null) return;
    final entry = _sessions.remove(sid);
    if (entry != null) {
      try { await entry.session.dispose(); } catch (_) {}
    }
  }

  String? _extractSid(String url) {
    final m = RegExp(r'/master/([^/]+)/').firstMatch(url);
    return m?.group(1);
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    req.response.headers.set('Access-Control-Allow-Origin', '*');

    try {
      // /master/<sid>/playlist.m3u8 — fetch upstream m3u8, rewrite .ts URLs
      // so segments come back through us (and signing happens per-segment).
      final masterMatch = RegExp(r'^/master/([^/]+)/playlist\.m3u8$').firstMatch(path);
      if (masterMatch != null) {
        final sid = masterMatch.group(1)!;
        final entry = _sessions[sid];
        if (entry == null) {
          req.response.statusCode = 410;
          await req.response.close();
          return;
        }
        await _serveMaster(req, sid, entry);
        return;
      }

      // /segment/<sid>/<base64url> — forward to WebView's signed fetch and
      // stream the binary body back to ExoPlayer.
      final segMatch = RegExp(r'^/segment/([^/]+)/(.+)$').firstMatch(path);
      if (segMatch != null) {
        final sid = segMatch.group(1)!;
        final encoded = segMatch.group(2)!;
        final entry = _sessions[sid];
        if (entry == null) {
          req.response.statusCode = 410;
          await req.response.close();
          return;
        }
        await _serveSegment(req, entry, encoded);
        return;
      }

      req.response.statusCode = 404;
      await req.response.close();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[UzProxy] handler error: $e\n$st');
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveMaster(HttpRequest req, String sid, _Entry entry) async {
    _touch(entry);
    final res = await entry.session.fetchSigned(entry.masterUrl);
    if (!res.ok || res.status >= 400) {
      req.response.statusCode = res.status >= 100 ? res.status : 502;
      await req.response.close();
      return;
    }
    var body = utf8.decode(res.body, allowMalformed: true);
    final masterUri = Uri.parse(entry.masterUrl);
    final rewritten = _rewriteM3u8(
      body: body,
      masterUri: masterUri,
      proxyBase: 'http://127.0.0.1:$_port',
      sid: sid,
    );
    final out = utf8.encode(rewritten);
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
    req.response.headers.contentLength = out.length;
    req.response.add(out);
    await req.response.close();
  }

  Future<void> _serveSegment(HttpRequest req, _Entry entry, String encoded) async {
    _touch(entry);
    String upstreamUrl;
    try {
      upstreamUrl = utf8.decode(base64Url.decode(_padBase64(encoded)));
    } catch (e) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }
    final res = await entry.session.fetchSigned(upstreamUrl);
    if (!res.ok || res.status >= 400) {
      req.response.statusCode = res.status >= 100 ? res.status : 502;
      await req.response.close();
      return;
    }
    req.response.statusCode = 200;
    if (res.contentType.isNotEmpty) {
      try { req.response.headers.set(HttpHeaders.contentTypeHeader, res.contentType); }
      catch (_) {}
    }
    req.response.headers.contentLength = res.body.length;
    req.response.add(res.body);
    await req.response.close();
  }

  // Rewrites every segment / variant URL in a playlist to route through us.
  // Resolves relative paths against the master URL first.
  String _rewriteM3u8({
    required String body,
    required Uri masterUri,
    required String proxyBase,
    required String sid,
  }) {
    final lines = body.split('\n');
    final out = StringBuffer();
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        out.writeln(raw);
        continue;
      }
      if (line.startsWith('#')) {
        // Some tags embed URIs (EXT-X-KEY, EXT-X-MAP, EXT-X-MEDIA subtitles).
        final rewritten = line.replaceAllMapped(
          RegExp(r'URI="([^"]+)"'),
          (m) {
            final u = _resolveAndProxy(m.group(1)!, masterUri, proxyBase, sid);
            return 'URI="$u"';
          },
        );
        out.writeln(rewritten);
        continue;
      }
      out.writeln(_resolveAndProxy(line, masterUri, proxyBase, sid));
    }
    return out.toString();
  }

  String _resolveAndProxy(String url, Uri masterUri, String proxyBase, String sid) {
    final absolute = Uri.parse(url).hasAuthority ? Uri.parse(url) : masterUri.resolve(url);
    final encoded = base64Url.encode(utf8.encode(absolute.toString())).replaceAll('=', '');
    return '$proxyBase/segment/$sid/$encoded';
  }

  String _padBase64(String s) {
    final pad = (4 - s.length % 4) % 4;
    return s + ('=' * pad);
  }
}

class _Entry {
  final UzmoviProxySession session;
  final String masterUrl;
  DateTime lastAccess;
  _Entry({required this.session, required this.masterUrl})
      : lastAccess = DateTime.now();
}
