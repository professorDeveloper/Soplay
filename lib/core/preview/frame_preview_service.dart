import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// On-device seek-preview frames generated natively (MediaMetadataRetriever) for
/// providers that don't ship VTT/storyboard thumbnails (e.g. all CloudStream
/// ones). Android-only; no-op elsewhere. Frames are cached by bucketed position
/// so scrubbing only extracts a handful.
class FramePreviewService {
  FramePreviewService._();

  static const MethodChannel _ch = MethodChannel('soplay/preview');
  // Android: MediaMetadataRetriever (progressive only). iOS: AVAssetImageGenerator
  // (progressive AND HLS). Both implement the `soplay/preview` channel.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

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
    // Only cache successes. A null here usually means the retriever is still
    // opening (first scrub race) — caching it would permanently show a
    // placeholder for that bucket; instead let the next scrub retry.
    if (bytes != null) _cache[bucket] = bytes;
    return bytes;
  }

  /// Ensure the URL is open (idempotent) then return the bucketed frame.
  ///
  /// Both steps are time-boxed: a network `setDataSource` (open) or an
  /// unsupported source (e.g. HLS) must never leave the player's preview spinner
  /// hanging. On timeout we return null and the caller shows a static fallback;
  /// the open keeps warming up in the background so later scrubs can succeed.
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
    if (!isSupported) return;
    try {
      await _ch.invokeMethod('close');
    } catch (_) {}
  }
}
