import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';

void main() {
  group('LocalHlsProxy', () {
    late _MockUpstream upstream;
    late LocalHlsProxy proxy;
    late Dio dio;

    setUp(() async {
      upstream = await _MockUpstream.start();
      dio = Dio(BaseOptions(validateStatus: (_) => true));
      proxy = LocalHlsProxy(dio);
    });

    tearDown(() async {
      await proxy.dispose();
      await upstream.close();
      dio.close(force: true);
    });

    test('does not forward Origin to upstream', () async {
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\n#EXT-X-VERSION:3\n',
      );

      final loopback = await proxy.register(
        upstreamUrl:
            '${upstream.origin}/cdn/manifest/video/x.m3u8?sec=token123',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13)',
          'Referer': 'https://www.dailymotion.com/',
          'Origin': 'https://www.dailymotion.com',
        },
      );

      final body = await _httpGetString(loopback);
      expect(body, contains('#EXTM3U'));

      final received = upstream.lastHeaders;
      expect(received, isNotNull);
      expect(received!.containsKey('origin'), isFalse,
          reason: 'Origin must be stripped before sending upstream');
      expect(received['user-agent'], contains('Android'));
      expect(received['referer'], 'https://www.dailymotion.com/');
    });

    test('rewrites same-host playlist URIs to loopback paths', () async {
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=800000\n'
            '${upstream.origin}/cdn/manifest/video/variant_low.m3u8?sec=tok\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2000000\n'
            'variant_high.m3u8\n',
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8?sec=tok',
        headers: const {'User-Agent': 'test'},
      );

      final body = await _httpGetString(loopback);

      final loopbackUri = Uri.parse(loopback);
      final base = '/hls/${loopbackUri.pathSegments[1]}';
      expect(body,
          contains('$base/cdn/manifest/video/variant_low.m3u8?sec=tok'));
      expect(body,
          contains('$base/cdn/manifest/video/variant_high.m3u8'));
    });

    test('rewrites cross-host segment URIs into base64 _h/ form', () async {
      const altHost = '127.0.0.1';
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1000000\n'
            'https://$altHost:1/seg/720p.m3u8?t=1\n',
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8',
        headers: const {'User-Agent': 'test'},
      );

      final body = await _httpGetString(loopback);
      final expectedTag = base64UrlEncode(utf8.encode('$altHost:1'))
          .replaceAll('=', '');
      expect(body, contains('/_h/$expectedTag/seg/720p.m3u8?t=1'));
    });

    test('forwards binary segment bytes verbatim', () async {
      final segmentBytes = List<int>.generate(256, (i) => i % 256);
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\nseg0.ts\n',
      );
      upstream.respondBytes(
        path: '/cdn/manifest/video/seg0.ts',
        contentType: 'video/MP2T',
        body: segmentBytes,
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8',
        headers: const {'User-Agent': 'test'},
      );

      final manifestBody = await _httpGetString(loopback);
      final loopbackUri = Uri.parse(loopback);
      final base =
          'http://127.0.0.1:${loopbackUri.port}/hls/${loopbackUri.pathSegments[1]}';
      expect(manifestBody, contains('$base/cdn/manifest/video/seg0.ts'));

      final segBytes =
          await _httpGetBytes('$base/cdn/manifest/video/seg0.ts');
      expect(segBytes, equals(segmentBytes));
    });

    test('returns 410 for unknown session id', () async {
      await proxy.register(
        upstreamUrl:
            '${upstream.origin}/cdn/manifest/video/x.m3u8?sec=tok',
        headers: const {'User-Agent': 'test'},
      );
      final port = proxy.debugPort;
      final res = await _httpGetStatus(
          'http://127.0.0.1:$port/hls/deadbeef/cdn/manifest/video/x.m3u8');
      expect(res, 410);
    });

    test('returns upstream status code on 4xx', () async {
      upstream.respondStatus(
        path: '/cdn/manifest/video/x.m3u8',
        status: 403,
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8',
        headers: const {'User-Agent': 'test'},
      );
      final status = await _httpGetStatus(loopback);
      expect(status, 403);
    });
  });
}

class _MockUpstream {
  _MockUpstream._(this._server);

  final HttpServer _server;
  final Map<String, _MockResponse> _routes = {};
  Map<String, String>? lastHeaders;

  String get origin => 'http://${_server.address.host}:${_server.port}';

  static Future<_MockUpstream> start() async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockUpstream._(server);
    server.listen(mock._handle);
    return mock;
  }

  void respond({
    required String path,
    required String body,
    String? contentType,
  }) {
    _routes[path] = _MockResponse(
      status: 200,
      bytes: utf8.encode(body),
      contentType: contentType,
    );
  }

  void respondBytes({
    required String path,
    required List<int> body,
    String? contentType,
  }) {
    _routes[path] = _MockResponse(
      status: 200,
      bytes: body,
      contentType: contentType,
    );
  }

  void respondStatus({required String path, required int status}) {
    _routes[path] = _MockResponse(status: status, bytes: const []);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    lastHeaders = {};
    req.headers.forEach((name, values) {
      lastHeaders![name.toLowerCase()] = values.join(',');
    });
    final route = _routes[req.uri.path];
    if (route == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response.statusCode = route.status;
    if (route.contentType != null) {
      req.response.headers
          .set(HttpHeaders.contentTypeHeader, route.contentType!);
    }
    req.response.add(route.bytes);
    await req.response.close();
  }
}

class _MockResponse {
  _MockResponse({required this.status, required this.bytes, this.contentType});
  final int status;
  final List<int> bytes;
  final String? contentType;
}

Future<String> _httpGetString(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return body;
  } finally {
    client.close();
  }
}

Future<List<int>> _httpGetBytes(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    return out;
  } finally {
    client.close();
  }
}

Future<int> _httpGetStatus(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close();
  }
}
