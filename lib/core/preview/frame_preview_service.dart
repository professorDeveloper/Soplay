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
  // Buckets currently being prefetched, so neighbour warm-ups aren't requested
  // twice while one is still in flight.
  static final Set<int> _inFlight = {};

  /// Bucket size (ms) — one frame per this window is extracted & cached.
  static const int bucketMs = 5000;

  /// Open [url] for preview extraction. [warmMs] (defaults to the start) tells
  /// the native side which frame to warm the decoder with up front, so the first
  /// scrub already has a frame ready instead of paying codec-init then.
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

  /// Frame for [positionMs] (bucketed + cached). Returns null when unavailable.
  static Future<Uint8List?> frame(int positionMs) async {
    if (!isSupported || _openUrl == null) return null;
    final bucket = (positionMs ~/ bucketMs) * bucketMs;
    if (_cache.containsKey(bucket)) return _cache[bucket];
    final bytes = await _extract(bucket);
    // Only cache successes. A null here usually means the retriever is still
    // opening (first scrub race) — caching it would permanently show a
    // placeholder for that bucket; instead let the next scrub retry.
    if (bytes != null) {
      _cache[bucket] = bytes;
      // Warm the neighbouring buckets so continued scrubbing is instant. These
      // run in the background and only populate the cache; a failure is ignored.
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

  /// Fire-and-forget extraction of [bucket] into the cache (no spinner, no UI).
  static void _prefetch(int bucket) {
    if (bucket < 0 || _openUrl == null) return;
    if (_cache.containsKey(bucket) || _inFlight.contains(bucket)) return;
    _inFlight.add(bucket);
    _extract(bucket).then((bytes) {
      _inFlight.remove(bucket);
      if (bytes != null) _cache[bucket] = bytes;
    });
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
    _inFlight.clear();
    if (!isSupported) return;
    try {
      await _ch.invokeMethod('close');
    } catch (_) {}
  }
}
