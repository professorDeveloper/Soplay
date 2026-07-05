import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Cross-platform orientation lock.
///
/// On iOS we route through a native MethodChannel because Flutter 3.41's
/// scene-based lifecycle doesn't reliably propagate
/// `SystemChrome.setPreferredOrientations` to the active view controller,
/// surfacing as `UISceneErrorDomain Code=101` errors at runtime. On Android
/// (and anywhere else) the standard SystemChrome path works fine.
class AppOrientation {
  AppOrientation._();

  static const _channel = MethodChannel('app/orientation');

  static Future<void> set(List<DeviceOrientation> orientations) async {
    // Orientation locking is a mobile-only concern — no-op on desktop/web so
    // callers don't each have to guard it.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod<void>('set', {
          'modes': orientations.map(_name).toList(),
        });
      } catch (_) {
        // Fall back to SystemChrome if the channel isn't wired (e.g.
        // older binary, hot-reload race).
        await SystemChrome.setPreferredOrientations(orientations);
      }
      return;
    }
    await SystemChrome.setPreferredOrientations(orientations);
  }

  static String _name(DeviceOrientation o) => switch (o) {
        DeviceOrientation.portraitUp => 'portraitUp',
        DeviceOrientation.portraitDown => 'portraitDown',
        DeviceOrientation.landscapeLeft => 'landscapeLeft',
        DeviceOrientation.landscapeRight => 'landscapeRight',
      };
}
