import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class AniyomiChannel {
  AniyomiChannel._();

  static const MethodChannel _ch = MethodChannel('soplay/aniyomi');

  static bool get isSupported => Platform.isAndroid;

  static final StreamController<({int current, int total})> _progressCtrl =
      StreamController<({int current, int total})>.broadcast();
  static bool _handlerSet = false;

  static void _ensureHandler() {
    if (_handlerSet || !isSupported) return;
    _handlerSet = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'installProgress') {
        final a = call.arguments;
        if (a is Map) {
          _progressCtrl.add((
            current: (a['current'] as num?)?.toInt() ?? 0,
            total: (a['total'] as num?)?.toInt() ?? 0,
          ));
        }
      }
      return null;
    });
  }

  static Stream<({int current, int total})> get installProgress {
    _ensureHandler();
    return _progressCtrl.stream;
  }

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) return null;
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Map<String, dynamic> _obj(String? s) {
    if (s == null || s.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(s);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static List<dynamic> _arr(String? s) {
    if (s == null || s.isEmpty) return const [];
    final decoded = jsonDecode(s);
    return decoded is List ? decoded : const [];
  }

  static Future<List<dynamic>> listProviders() async =>
      _arr(await _call<String>('listProviders'));

  static Future<List<dynamic>> ensureLoaded() async =>
      _arr(await _call<String>('ensureLoaded'));

  static Future<List<dynamic>> listRepos() async =>
      _arr(await _call<String>('listRepos'));

  static Future<Map<String, dynamic>> removeRepo(String url) async =>
      _obj(await _call<String>('removeRepo', {'url': url}));

  static Future<Map<String, dynamic>> addRepo(String url) async =>
      _obj(await _call<String>('addRepo', {'url': url}));

  static Future<List<dynamic>> getGenres(String provider) async =>
      _arr(await _call<String>('getGenres', {'provider': provider}));

  static Future<Map<String, dynamic>> getMainPage(String provider,
          {int page = 1}) async =>
      _obj(await _call<String>('getMainPage', {'provider': provider, 'page': page}));

  static Future<Map<String, dynamic>> getSection(
    String provider,
    String data, {
    int page = 1,
  }) async =>
      _obj(await _call<String>(
          'getSection', {'provider': provider, 'data': data, 'page': page}));

  static Future<Map<String, dynamic>> search(String provider, String query) async =>
      _obj(await _call<String>('search', {'provider': provider, 'query': query}));

  static Future<Map<String, dynamic>> load(String provider, String url) async =>
      _obj(await _call<String>('load', {'provider': provider, 'url': url}));

  static Future<Map<String, dynamic>> loadLinks(String provider, String data) async =>
      _obj(await _call<String>('loadLinks', {'provider': provider, 'data': data}));
}
