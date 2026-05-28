import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

/// In-process loopback HLS proxy.
///
/// Upstream HLS hosts that bind their signed manifest URLs to the client IP
/// (e.g. Dailymotion's `cdndirector.dailymotion.com`) reject ExoPlayer
/// requests when the manifest was solved by one socket and the player opens
/// another. Routing the player through this loopback server forces every
/// upstream socket — manifest, variant playlists, segments — through the
/// same Dio instance that already holds the session cookies, so the IP and
/// cookies match end-to-end.
///
/// Source-agnostic: it activates only when a [VideoSourceEntity] arrives
/// with `useLocalProxy: true`. The mobile side never names a provider.
class LocalHlsProxy {
  LocalHlsProxy(this._dio);

  static const _sessionTtl = Duration(minutes: 30);
  static const _cleanupInterval = Duration(minutes: 5);

  final Dio _dio;
  HttpServer? _server;
  int? _port;
  Timer? _cleanupTimer;
  final Map<String, _Session> _sessions = {};

  @visibleForTesting
  int? get debugPort => _port;

  Future<String> register({
    required String upstreamUrl,
    required Map<String, String> headers,
  }) async {
    await _ensureStarted();
    final id = _randomId();
    final parsed = Uri.parse(upstreamUrl);
    final lastSlash = parsed.path.lastIndexOf('/');
    final basePath = lastSlash >= 0 ? parsed.path.substring(0, lastSlash) : '';
    _sessions[id] = _Session(
      origin: '${parsed.scheme}://${parsed.authority}',
      basePath: basePath,
      cdnQuery: parsed.query,
      headers: Map<String, String>.from(headers),
      lastAccess: DateTime.now(),
    );
    final query = parsed.hasQuery ? '?${parsed.query}' : '';
    return 'http://127.0.0.1:$_port/hls/$id${parsed.path}$query';
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _sessions.clear();
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('[HLS_PROXY] listening on 127.0.0.1:$_port');
    _server!.listen(_handle, onError: (Object e) {
      debugPrint('[HLS_PROXY] server error: $e');
    });
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _evictStale());
  }

  void _evictStale() {
    final now = DateTime.now();
    _sessions.removeWhere(
      (_, s) => now.difference(s.lastAccess) > _sessionTtl,
    );
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.requestedUri.path;
    final match = RegExp(r'^/hls/([a-f0-9]+)(/.*)$').firstMatch(path);
    if (match == null) {
      await _reject(req, 404);
      return;
    }
    final sid = match.group(1)!;
    var cdnPath = match.group(2)!;
    final sess = _sessions[sid];
    if (sess == null) {
      await _reject(req, 410);
      return;
    }
    sess.lastAccess = DateTime.now();

    var origin = sess.origin;
    final hMatch =
        RegExp(r'^/_h/([A-Za-z0-9_-]+)(/.*)$').firstMatch(cdnPath);
    if (hMatch != null) {
      try {
        origin = 'https://${_b64UrlDecode(hMatch.group(1)!)}';
        cdnPath = hMatch.group(2)!;
      } catch (_) {
        await _reject(req, 400);
        return;
      }
    }

    final resolved =
        cdnPath.startsWith(sess.basePath) || origin != sess.origin
            ? cdnPath
            : '${sess.basePath}$cdnPath';
    final queryString = req.requestedUri.hasQuery
        ? '?${req.requestedUri.query}'
        : (origin == sess.origin && sess.cdnQuery.isNotEmpty
            ? '?${sess.cdnQuery}'
            : '');
    final upstreamUrl = '$origin$resolved$queryString';

    final upstreamHeaders = <String, String>{};
    sess.headers.forEach((k, v) {
      final lower = k.toLowerCase();
      if (lower == 'origin' || lower == 'host' || lower == 'content-length') {
        return;
      }
      upstreamHeaders[k] = v;
    });

    try {
      final resp = await _dio.get<List<int>>(
        upstreamUrl,
        options: Options(
          headers: upstreamHeaders,
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );
      final status = resp.statusCode ?? 502;
      if (status >= 400) {
        debugPrint(
          '[HLS_PROXY] upstream $status: $upstreamUrl '
          'sent=${upstreamHeaders.keys.toList()}',
        );
        await _reject(req, status);
        return;
      }

      final contentType =
          (resp.headers.value('content-type') ?? '').toLowerCase();
      final isManifest = contentType.contains('mpegurl') ||
          contentType.contains('m3u8') ||
          resolved.endsWith('.m3u8');
      final body = resp.data ?? const <int>[];

      if (isManifest) {
        if (origin == sess.origin) {
          final lastSlash = resolved.lastIndexOf('/');
          if (lastSlash >= 0) {
            sess.basePath = resolved.substring(0, lastSlash);
          }
        }
        final text = utf8.decode(body, allowMalformed: true);
        String rewritten;
        try {
          rewritten = _rewriteM3u8(
            text,
            base: '/hls/$sid',
            sessionOrigin: sess.origin,
            upstreamUrl: upstreamUrl,
          );
        } catch (e, st) {
          debugPrint('[HLS_PROXY] rewrite error: $e\n$st');
          rewritten = text;
        }
        req.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        req.response.add(utf8.encode(rewritten));
      } else {
        if (contentType.isNotEmpty) {
          req.response.headers
              .set(HttpHeaders.contentTypeHeader, contentType);
        }
        final len = resp.headers.value('content-length');
        if (len != null) {
          req.response.headers.set(HttpHeaders.contentLengthHeader, len);
        }
        req.response.add(body);
      }
      await req.response.close();
    } catch (e) {
      debugPrint('[HLS_PROXY] error: $e');
      await _reject(req, 502);
    }
  }

  Future<void> _reject(HttpRequest req, int status) async {
    try {
      req.response.statusCode = status;
      await req.response.close();
    } catch (_) {}
  }

  String _rewriteM3u8(
    String content, {
    required String base,
    required String sessionOrigin,
    required String upstreamUrl,
  }) {
    final sessionHost = Uri.parse(sessionOrigin).host;
    final upstreamUri = Uri.parse(upstreamUrl);

    String rewriteUrl(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return raw;
      Uri abs;
      try {
        final parsed = Uri.parse(trimmed);
        abs = parsed.isAbsolute ? parsed : upstreamUri.resolveUri(parsed);
      } catch (_) {
        return '$base/$trimmed';
      }
      final query = abs.hasQuery ? '?${abs.query}' : '';
      if (abs.host == sessionHost) {
        return '$base${abs.path}$query';
      }
      final tag = _b64UrlEncode(abs.host);
      return '$base/_h/$tag${abs.path}$query';
    }

    final keyAttrPattern = RegExp(r'URI="([^"]+)"');
    final lines = content.split('\n');
    final out = <String>[];
    for (final line in lines) {
      final stripped = line.trim();
      if (stripped.isEmpty) {
        out.add(line);
        continue;
      }
      if (stripped.startsWith('#')) {
        out.add(line.replaceAllMapped(
          keyAttrPattern,
          (m) => 'URI="${rewriteUrl(m.group(1)!)}"',
        ));
        continue;
      }
      out.add(rewriteUrl(line));
    }
    return out.join('\n');
  }

  static final _hex = '0123456789abcdef';
  static final _rng = Random.secure();

  String _randomId() {
    return List.generate(24, (_) => _hex[_rng.nextInt(16)]).join();
  }

  String _b64UrlEncode(String s) =>
      base64UrlEncode(utf8.encode(s)).replaceAll('=', '');

  String _b64UrlDecode(String s) {
    final padded = s + '=' * ((4 - s.length % 4) % 4);
    return utf8.decode(base64Url.decode(padded));
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
