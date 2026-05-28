import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/core/router/app_router.dart';

/// Listens for incoming universal links and custom-scheme URLs and routes
/// them through go_router.
///
/// Accepted shapes (see `apple-app-site-association` and `assetlinks.json`
/// hosted on sozo.azamov.me):
///
///   https://sozo.azamov.me/detail?url=...
///   https://sozo.azamov.me/play?url=...&type=hls&provider=...
///   sozo://detail?url=...
///   sozo://play?url=...&type=hls
///
/// Unknown paths are ignored so a stale link can't crash the app.
class DeeplinkService {
  DeeplinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  static const _tag = '[Deeplink]';
  static const _host = 'sozo.azamov.me';
  static const _scheme = 'sozo';

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Starts listening for links. Call once after `runApp` so go_router has a
  /// context to navigate with.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('$_tag initial link failed: $e');
    }

    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('$_tag stream error: $e'),
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  void _handle(Uri uri) {
    debugPrint('$_tag received: $uri');

    final isUniversal = uri.scheme == 'https' && uri.host == _host;
    final isCustom = uri.scheme == _scheme;
    if (!isUniversal && !isCustom) {
      debugPrint('$_tag ignoring unknown link');
      return;
    }

    final path = uri.path.isEmpty ? '/${uri.host}' : uri.path;
    final query = uri.queryParameters;

    final route = _resolveRoute(path, query);
    if (route == null) {
      debugPrint('$_tag no route for path=$path');
      return;
    }

    debugPrint('$_tag routing to $route');
    AppRouter.router.go(route);
  }

  String? _resolveRoute(String path, Map<String, String> q) {
    // Normalize: for custom scheme, host becomes the first path segment.
    // soplay://detail?url=... → path "/detail" or "detail"
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    switch (segments.first) {
      case 'detail':
        final url = q['url']?.trim();
        if (url == null || url.isEmpty) return null;
        return '/detail?url=${Uri.encodeQueryComponent(url)}';
      case 'play':
      case 'player':
        // Player needs PlayerArgs via extra — universal link only opens
        // detail page which then triggers playback through normal UX.
        // Forwarding to detail is the safest entry point.
        final url = q['url']?.trim();
        if (url == null || url.isEmpty) return null;
        return '/detail?url=${Uri.encodeQueryComponent(url)}';
      default:
        return null;
    }
  }
}
