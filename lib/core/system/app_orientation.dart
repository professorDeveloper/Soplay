import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class AppOrientation {
  AppOrientation._();

  static const _channel = MethodChannel('app/orientation');

  static Future<void> set(List<DeviceOrientation> orientations) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod<void>('set', {
          'modes': orientations.map(_name).toList(),
        });
      } catch (_) {
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
