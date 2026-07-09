import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/core/storage/hive_service.dart';

class DeeplinkService {
  DeeplinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  static const _tag = '[Deeplink]';
  static const _host = 'sozo.azamov.me';
  static const _scheme = 'sozo';

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;
  bool _started = false;

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

  Future<void> _handle(Uri uri) async {
    debugPrint('$_tag received: $uri');

    final isUniversal = uri.scheme == 'https' && uri.host == _host;
    final isCustom = uri.scheme == _scheme;
    if (!isUniversal && !isCustom) {
      debugPrint('$_tag ignoring unknown link');
      return;
    }

    // Custom-scheme links encode the route in the authority:
    //   sozo://detail?url=…   -> /detail
    //   sozo://party/<CODE>   -> /party/<CODE>   (path segment carries the code)
    // Universal (https) links carry the whole route in the path already.
    final String path;
    if (isCustom && uri.host.isNotEmpty) {
      path = '/${uri.host}${uri.path}';
    } else {
      path = uri.path.isEmpty ? '/${uri.host}' : uri.path;
    }
    final query = uri.queryParameters;

    final provider = query['provider']?.trim();
    if (provider != null && provider.isNotEmpty) {
      try {
        await getIt<HiveService>().saveCurrentProvider(provider);
      } catch (e) {
        debugPrint('$_tag failed to save provider: $e');
      }
    }

    final route = _resolveRoute(path, query);
    if (route == null) {
      debugPrint('$_tag no route for path=$path');
      return;
    }

    debugPrint('$_tag routing to $route');
    AppRouter.router.go(route);
  }

  String? _resolveRoute(String path, Map<String, String> q) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    switch (segments.first) {
      case 'detail':
        final url = q['url']?.trim();
        if (url == null || url.isEmpty) return null;
        return _detailRoute(url, q['provider']?.trim());
      case 'play':
      case 'player':
        final url = q['url']?.trim();
        if (url == null || url.isEmpty) return null;
        return _detailRoute(url, q['provider']?.trim());
      case 'party':
        // Code lives in the PATH segment: /party/<CODE> — not a query param.
        final code = segments.length > 1 ? segments[1].trim() : '';
        if (code.isEmpty) return null;
        return '/watch-party?code=${Uri.encodeComponent(code)}';
      default:
        return null;
    }
  }

  String _detailRoute(String url, String? provider) {
    final params = <String, String>{'url': url};
    if (provider != null && provider.isNotEmpty) {
      params['provider'] = provider;
    }
    final qs = Uri(queryParameters: params).query;
    return '/detail?$qs';
  }
}
