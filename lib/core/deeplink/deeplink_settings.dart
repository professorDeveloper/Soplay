import 'package:flutter/services.dart';

class DeeplinkSettings {
  DeeplinkSettings._();

  static const _channel = MethodChannel('soplay/deeplink_settings');

  static Future<bool> openDefaultLinksSettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openDefaultLinksSettings');
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
