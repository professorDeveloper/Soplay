import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Dart bridge to the native CloudStream plugin host (`soplay/cloudstream`).
///
/// Android-only: on iOS every call is a no-op returning empty data, so callers
/// can use it unconditionally and CloudStream providers simply never appear on
/// iOS. The native side runs `.cs3` plugins in CloudStream's runtime and returns
/// JSON shaped like soplay's existing models (provider card / detail+episodes /
/// VideoSource / subtitle) — see android .../cloudstream/PluginHost.kt.
///
/// Provider ids are namespaced `cs:<name>` and content urls are the plugin
/// `load` urls, so my-list / continue-watching keep working unchanged.
class CloudStreamChannel {
  CloudStreamChannel._();

  static const MethodChannel _ch = MethodChannel('soplay/cloudstream');

  /// CloudStream plugins are Android DEX — unsupported on iOS.
  static bool get isSupported => Platform.isAndroid;

  static Future<String?> _call(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) return null;
    try {
      return await _ch.invokeMethod<String>(method, args);
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

  /// Registered CloudStream providers: `[{id:'cs:..', name, lang, types, ...}]`.
  static Future<List<dynamic>> listProviders() async => _arr(await _call('listProviders'));

  /// Re-load saved repos (once per process) and return the resulting providers.
  /// Call before reading the provider list so persisted sources reappear after
  /// an app restart.
  static Future<List<dynamic>> ensureLoaded() async => _arr(await _call('ensureLoaded'));

  /// Saved repo URLs/shortcodes: `["https://...", "code", ...]`.
  static Future<List<dynamic>> listRepos() async => _arr(await _call('listRepos'));

  /// Remove a saved repo (persistence only; providers clear on next launch).
  static Future<Map<String, dynamic>> removeRepo(String urlOrShortcode) async =>
      _obj(await _call('removeRepo', {'url': urlOrShortcode}));

  /// Add a repo by `repo.json`/`plugins.json` URL or a CloudStream shortcode.
  /// Returns `{repo, pluginCount, providers:[name...]}`.
  static Future<Map<String, dynamic>> addRepo(String urlOrShortcode) async =>
      _obj(await _call('addRepo', {'url': urlOrShortcode}));

  /// Home rows for a provider: `{provider, banner:[card], sections:[{label,items}]}`.
  static Future<Map<String, dynamic>> getMainPage(String provider, {int page = 1}) async =>
      _obj(await _call('getMainPage', {'provider': provider, 'page': page}));

  /// One home section ("view all"), paginated: `{provider, items, page, totalPages}`.
  static Future<Map<String, dynamic>> getSection(
    String provider,
    String data, {
    int page = 1,
  }) async =>
      _obj(await _call('getSection', {'provider': provider, 'data': data, 'page': page}));

  /// Search: `{provider, items:[card], query, page, totalPages}`.
  static Future<Map<String, dynamic>> search(String provider, String query) async =>
      _obj(await _call('search', {'provider': provider, 'query': query}));

  /// Detail + episodes: `{provider, contentUrl, title, ..., isSerial, episodes:[{episode,label,mediaRef}]}`.
  static Future<Map<String, dynamic>> load(String provider, String url) async =>
      _obj(await _call('load', {'provider': provider, 'url': url}));

  /// Resolve playable links: `{sources:[{quality,videoUrl,type,host,headers}], subtitles:[{label,file}]}`.
  static Future<Map<String, dynamic>> loadLinks(String provider, String data) async =>
      _obj(await _call('loadLinks', {'provider': provider, 'data': data}));
}
