import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// On-device seek-preview frames generated natively (MediaMetadataRetriever) for
/// providers that don't ship VTT/storyboard thumbnails (e.g. all CloudStream
/// ones). Android-only; no-op elsewhere. Frames are cached by bucketed position
/// so scrubbing only extracts a handful.
class FramePreviewService {
  FramePreviewService._();

  static const MethodChannel _ch = MethodChannel('soplay/preview');
  static bool get isSupported => Platform.isAndroid;

  static String? _openUrl;
  static final Map<int, Uint8List?> _cache = {};

  /// Bucket size (ms) — one frame per this window is extracted & cached.
  static const int bucketMs = 5000;

  static Future<void> open(String url, Map<String, String> headers) async {
    if (!isSupported) return;
    if (_openUrl == url) return;
    _openUrl = url;
    _cache.clear();
    try {
      await _ch.invokeMethod('open', {'url': url, 'headers': headers});
    } catch (_) {}
  }

  /// Frame for [positionMs] (bucketed + cached). Returns null when unavailable.
  static Future<Uint8List?> frame(int positionMs) async {
    if (!isSupported || _openUrl == null) return null;
    final bucket = (positionMs ~/ bucketMs) * bucketMs;
    if (_cache.containsKey(bucket)) return _cache[bucket];
    Uint8List? bytes;
    try {
      bytes = await _ch.invokeMethod<Uint8List>('frame', {'posMs': bucket});
    } catch (_) {
      bytes = null;
    }
    _cache[bucket] = bytes;
    return bytes;
  }

  /// Ensure the URL is open (idempotent) then return the bucketed frame.
  static Future<Uint8List?> previewFrame(
    String url,
    Map<String, String> headers,
    int positionMs,
  ) async {
    if (!isSupported) return null;
    await open(url, headers);
    return frame(positionMs);
  }

  static Future<void> close() async {
    _openUrl = null;
    _cache.clear();
    if (!isSupported) return;
    try {
      await _ch.invokeMethod('close');
    } catch (_) {}
  }
}
