import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';

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

  /// Android runs `.cs3` on-device; desktop reaches the same plugins through the
  /// local bridge (an emulator/device running the debug app). iOS: no-op.
  static bool get isSupported => Platform.isAndroid || ExtensionBridge.isEnabled;

  // Live install progress (current/total plugins) streamed from native during
  // [addRepo], so the install UI can show "Installing 12 / 65…" instead of an
  // opaque spinner on big repos.
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

  /// Stream of (current, total) plugin counts emitted while a repo installs.
  static Stream<({int current, int total})> get installProgress {
    _ensureHandler();
    return _progressCtrl.stream;
  }

  static Future<String?> _call(String method, [Map<String, dynamic>? args]) async {
    if (Platform.isAndroid) {
      try {
        return await _ch.invokeMethod<String>(method, args);
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    }
    if (ExtensionBridge.isEnabled) {
      return ExtensionBridge.instance.call('cloudstream', method, args);
    }
    return null;
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

  /// Remove a saved repo and unregister its providers immediately.
  static Future<Map<String, dynamic>> removeRepo(String url) async =>
      _obj(await _call('removeRepo', {'url': url}));

  /// Add a repo by `repo.json` / `plugins.json` URL.
  /// Returns `{repo, pluginCount, providers:[name...]}`.
  static Future<Map<String, dynamic>> addRepo(String url) async =>
      _obj(await _call('addRepo', {'url': url}));

  /// Re-check every saved repo for newer plugin versions and update them.
  /// Returns `{updated:[providerName...], count}`.
  static Future<Map<String, dynamic>> checkUpdates() async =>
      _obj(await _call('checkUpdates'));

  /// Provider categories for the home genre row: `[{provider,name,slug,image}]`.
  /// Tapping one opens its section via [getSection] (slug = MainPageData.data).
  static Future<List<dynamic>> getGenres(String provider) async =>
      _arr(await _call('getGenres', {'provider': provider}));

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
  static Future<Map<String, dynamic>> search(String provider, String query,
          {int page = 1}) async =>
      _obj(await _call('search', {'provider': provider, 'query': query, 'page': page}));

  /// Detail + episodes: `{provider, contentUrl, title, ..., isSerial, episodes:[{episode,label,mediaRef}]}`.
  static Future<Map<String, dynamic>> load(String provider, String url) async =>
      _obj(await _call('load', {'provider': provider, 'url': url}));

  /// Resolve playable links: `{sources:[{quality,videoUrl,type,host,headers}], subtitles:[{label,file}]}`.
  static Future<Map<String, dynamic>> loadLinks(String provider, String data) async =>
      _obj(await _call('loadLinks', {'provider': provider, 'data': data}));

  /// Base url + UA for the interactive Cloudflare solver: `{baseUrl, userAgent}`
  /// (or `{}` if the provider can't be resolved). [id] is the raw provider name
  /// (no `cs:` prefix).
  static Future<Map<String, dynamic>> cloudflareInfo(String id) async =>
      _obj(await _call('cloudflareInfo', {'id': id}));
}
