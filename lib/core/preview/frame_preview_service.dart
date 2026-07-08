import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class FramePreviewService {
  FramePreviewService._();

  static const MethodChannel _ch = MethodChannel('soplay/preview');
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static String? _openUrl;
  static final Map<int, Uint8List?> _cache = {};
  static final Set<int> _inFlight = {};

  static const int bucketMs = 5000;

  static Future<void> open(
    String url,
    Map<String, String> headers, {
    int warmMs = 0,
  }) async {
    if (!isSupported) return;
    if (_openUrl == url) return;
    _openUrl = url;
    _cache.clear();
    _inFlight.clear();
    final warmBucket = (warmMs ~/ bucketMs) * bucketMs;
    try {
      await _ch.invokeMethod(
        'open',
        {'url': url, 'headers': headers, 'warmMs': warmBucket},
      );
    } catch (_) {}
  }

  static Future<Uint8List?> frame(int positionMs) async {
    if (!isSupported || _openUrl == null) return null;
    final bucket = (positionMs ~/ bucketMs) * bucketMs;
    if (_cache.containsKey(bucket)) return _cache[bucket];
    final bytes = await _extract(bucket);
    if (bytes != null) {
      _cache[bucket] = bytes;
      _prefetch(bucket + bucketMs);
      _prefetch(bucket - bucketMs);
    }
    return bytes;
  }

  static Future<Uint8List?> _extract(int bucket) async {
    try {
      return await _ch.invokeMethod<Uint8List>('frame', {'posMs': bucket});
    } catch (_) {
      return null;
    }
  }

  static void _prefetch(int bucket) {
    if (bucket < 0 || _openUrl == null) return;
    if (_cache.containsKey(bucket) || _inFlight.contains(bucket)) return;
    _inFlight.add(bucket);
    _extract(bucket).then((bytes) {
      _inFlight.remove(bucket);
      if (bytes != null) _cache[bucket] = bytes;
    });
  }

  static Future<Uint8List?> previewFrame(
    String url,
    Map<String, String> headers,
    int positionMs,
  ) async {
    if (!isSupported) return null;
    await open(url, headers).timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    return frame(positionMs).timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
  }

  static Future<void> close() async {
    _openUrl = null;
    _cache.clear();
    _inFlight.clear();
    if (!isSupported) return;
    try {
      await _ch.invokeMethod('close');
    } catch (_) {}
  }
}
