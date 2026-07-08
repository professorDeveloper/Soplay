import 'package:flutter/services.dart';

class SystemControls {
  SystemControls._();

  static const MethodChannel _ch = MethodChannel('soplay/system_controls');

  static Future<double> getBrightness() async {
    try {
      final v = await _ch.invokeMethod<double>('getBrightness');
      return v ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  static Future<void> setBrightness(double value) async {
    try {
      await _ch.invokeMethod('setBrightness', {'value': value.clamp(0.0, 1.0)});
    } catch (_) {}
  }

  static Future<void> resetBrightness() async {
    try {
      await _ch.invokeMethod('resetBrightness');
    } catch (_) {}
  }
}
