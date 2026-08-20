import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'package:soplay/core/js/js_log.dart';

class WebViewEnv {
  WebViewEnv._();

  static const int _maxProfiles = 4;

  static WebViewEnvironment? _env;
  static Future<WebViewEnvironment?>? _pending;
  static int _profile = 0;
  static bool _exhausted = false;

  static bool get _isWindows => Platform.isWindows;

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
