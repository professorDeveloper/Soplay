import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'package:riasdxd/core/js/js_log.dart';

/// WebView2 (Windows) keeps its profile in a *user data folder*. Left to itself
/// the plugin puts that folder next to the .exe and locks it for the lifetime of
/// the browser process — so a machine-wide install (read-only dir), a second
/// running window, or an `msedgewebview2.exe` orphaned by a crash all make every
/// headless webview fail with "Cannot create the HeadlessInAppWebView instance!".
/// That kills the JS runtime, and with it every client/hybrid provider.
///
/// So: own the folder (under the per-user app-support dir, always writable) and,
/// when it turns out to be locked, move to the next one.
class WebViewEnv {
  WebViewEnv._();

  static const int _maxProfiles = 4;

  static WebViewEnvironment? _env;
  static Future<WebViewEnvironment?>? _pending;
  static int _profile = 0;
  static bool _exhausted = false;

  static bool get _isWindows => Platform.isWindows;

  /// The environment every webview must be created with. `null` on platforms
  /// where WebView2 isn't the backend (Android/iOS/macOS) — passing `null` there
  /// is what the plugin expects anyway.
  static Future<WebViewEnvironment?> ensure() async {
    if (!_isWindows || _exhausted) return null;
    final ready = _env;
    if (ready != null) return ready;
    return _pending ??= _create().whenComplete(() => _pending = null);
  }

  static Future<WebViewEnvironment?> _create() async {
    final Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } catch (e) {
      JsLog.err('webview2', 'no app-support dir: $e');
      return null;
    }

    // A locked profile fails right here with "The requested resource is in use" —
    // walk to the next one rather than leaving the app without a webview.
    while (_profile < _maxProfiles) {
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}webview2'
        '${_profile == 0 ? '' : '_$_profile'}',
      );
      try {
        await dir.create(recursive: true);
        final env = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: dir.path),
        );
        JsLog.info('webview2', 'profile ready: ${dir.path}');
        _env = env;
        return env;
      } catch (e) {
        JsLog.err('webview2', 'profile $_profile unusable: $e');
        _profile++;
      }
    }

    _exhausted = true;
    JsLog.err('webview2', 'all $_maxProfiles profiles locked — giving up');
    return null;
  }

  /// Called when a webview refused to start even though the environment itself
  /// was created: the profile is half-owned by somebody else, so drop it and
  /// build a fresh one. Returns false once we've run out of profiles to try.
  static Future<bool> rotate() async {
    if (!_isWindows || _exhausted) return false;
    final old = _env;
    _env = null;
    try {
      await old?.dispose();
    } catch (_) {}
    _profile++;
    JsLog.info('webview2', 'rotating to profile $_profile');
    return await ensure() != null;
  }
}
