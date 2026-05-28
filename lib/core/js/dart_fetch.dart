import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../network/cf_bypass_service.dart';
import 'js_log.dart';
import 'safe_cookie_manager.dart';

/// HTTP bridge for JS extractors. Runs every call through dio so we can:
///   - keep cookies sticky inside a single playback session (per-host
///     CookieJar)
///   - solve Cloudflare challenges on the device itself when the upstream
///     site is CF-protected (PrimeSrc et al.); the resulting cookies are
///     cached against the host and reused on subsequent requests
///   - report the cf_clearance back to the backend via /api/cf-cookies so
///     server-side providers also benefit
class DartFetch {
  final Dio _dio;
  final CfBypassService? _cfService;
  final Dio? _backendDio;

  /// Maps host → cookie header solved earlier in this session. Stored here
  /// in addition to the dio CookieJar so subsequent JS calls see them even
  /// if the upstream resets cookies between requests.
  final Map<String, String> _savedCookies = {};

  DartFetch._(this._dio, this._cfService, this._backendDio);

  /// Exposed so the in-process HLS proxy can talk to upstream CDNs with the
  /// same cookie jar — extractors save dailymotion session cookies in this
  /// jar and the proxy must replay them on segment requests.
  Dio get dio => _dio;

  /// `backendDio` is the app-wide dio used to POST solved cookies to
  /// `/api/cf-cookies`. Both params are optional — if either is missing the
  /// CF bypass simply doesn't run and a 428 propagates back to the JS side
  /// as a normal response.
  factory DartFetch.create({CfBypassService? cfService, Dio? backendDio}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: true,
        maxRedirects: 10,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    )..interceptors.add(SafeCookieManager(CookieJar()));
    return DartFetch._(dio, cfService, backendDio);
  }

  Future<Map<String, dynamic>> call(dynamic raw) async {
    final req = _coerceRequest(raw);
    if (req == null) {
      return const {'status': 0, 'data': null, 'headers': {}};
    }
    return _send(req, allowCfRetry: true);
  }

  Future<Map<String, dynamic>> _send(
    _Request req, {
    required bool allowCfRetry,
  }) async {
    final sw = Stopwatch()..start();
    JsLog.req('fetch', '${req.method} ${_shortUrl(req.url)}');

    // Inject cached CF cookies for the target host if we have them — saves a
    // round-trip on every subsequent extractor call once the challenge has
    // been solved once.
    final host = _hostOf(req.url);
    final extraHeaders = Map<String, String>.from(req.headers);
    if (host != null) {
      final cached = _savedCookies[host];
      if (cached != null) {
        final existing = extraHeaders['Cookie'] ?? extraHeaders['cookie'];
        extraHeaders['Cookie'] =
            existing != null ? '$cached; $existing' : cached;
      }
    }

    try {
      final response = await _dio.request<String>(
        req.url,
        data: req.body,
        options: Options(
          method: req.method,
          headers: extraHeaders,
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );
      final headers = <String, String>{};
      response.headers.forEach((k, v) => headers[k] = v.join(','));
      final status = response.statusCode ?? 0;

      // Detect Cloudflare challenge → solve and retry once.
      final cf = _cfService;
      if (allowCfRetry &&
          host != null &&
          cf != null &&
          _looksLikeCfChallenge(status, headers, response.data)) {
        JsLog.req('fetch', 'CF challenge on $host — solving …');
        final cookieHeader = await cf.solve(
          host: host,
          url: req.url,
          userAgent: req.headers['User-Agent'] ??
              req.headers['user-agent'] ??
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
        );
        if (cookieHeader != null) {
          _savedCookies[host] = cookieHeader;
          // Best-effort echo to backend so server-side flows also benefit.
          unawaited(_pushCookiesToBackend(host, cookieHeader, req.headers));
          return _send(req, allowCfRetry: false);
        }
      }

      JsLog.res(
        'fetch',
        '${req.method} ${_shortUrl(req.url)}',
        status: status,
        ms: sw.elapsedMilliseconds,
      );
      return {
        'status': status,
        'data': _decodeBody(response.data, headers['content-type']),
        'headers': headers,
      };
    } catch (e) {
      JsLog.err('fetch', '${req.method} ${_shortUrl(req.url)} — $e');
      return const {'status': 0, 'data': null, 'headers': {}};
    }
  }

  bool _looksLikeCfChallenge(int status, Map<String, String> headers, String? body) {
    if (status == 428 && body != null && body.contains('cfChallenge')) {
      return true;
    }
    if (status != 403 && status != 503) return false;
    final server = (headers['server'] ?? '').toLowerCase();
    if (server.contains('cloudflare')) return true;
    if (body == null) return false;
    return body.contains('cdn-cgi/challenge-platform') ||
        body.contains('__cf_chl_') ||
        body.contains('Just a moment...');
  }

  Future<void> _pushCookiesToBackend(
    String host,
    String cookies,
    Map<String, String> reqHeaders,
  ) async {
    final dio = _backendDio;
    if (dio == null) return;
    try {
      await dio.post(
        '/cf-cookies',
        data: {
          'host': host,
          'cookies': cookies,
          'userAgent': reqHeaders['User-Agent'] ?? reqHeaders['user-agent'] ?? '',
        },
        options: Options(extra: const {'skipCfBypassInterceptor': true}),
      );
    } catch (_) {
      // Non-fatal — the backend will just see another 428 next time.
    }
  }

  String? _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return null;
    }
  }

  String _shortUrl(String url) {
    if (url.length <= 90) return url;
    return '${url.substring(0, 80)}…';
  }

  _Request? _coerceRequest(dynamic raw) {
    if (raw is! Map) return null;
    final url = raw['url'] as String?;
    if (url == null || url.isEmpty) return null;
    final method = (raw['method'] as String? ?? 'GET').toUpperCase();
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k is String && v != null) headers[k] = v.toString();
      });
    }
    final body = raw['body'];
    return _Request(
      method: method,
      url: url,
      headers: headers,
      body: body,
    );
  }

  dynamic _decodeBody(String? data, String? contentType) {
    if (data == null || data.isEmpty) return data;
    if (contentType != null && contentType.toLowerCase().contains('application/json')) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }
}

class _Request {
  final String method;
  final String url;
  final Map<String, String> headers;
  final dynamic body;

  const _Request({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });
}
