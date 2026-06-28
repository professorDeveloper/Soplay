import 'package:flutter/services.dart';

/// Thin reusable wrapper over the native `soplay/system_controls` channel
/// (screen brightness / volume). Used by the player and the manga reader.
class SystemControls {
  SystemControls._();

  static const MethodChannel _ch = MethodChannel('soplay/system_controls');

  /// Current window brightness in 0..1 (best-effort; 0.5 on failure).
  static Future<double> getBrightness() async {
    try {
      final v = await _ch.invokeMethod<double>('getBrightness');
      return v ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  /// Override the window brightness (0..1).
  static Future<void> setBrightness(double value) async {
    try {
      await _ch.invokeMethod('setBrightness', {'value': value.clamp(0.0, 1.0)});
    } catch (_) {}
  }

  /// Release the brightness override, restoring the system default.
  static Future<void> resetBrightness() async {
    try {
      await _ch.invokeMethod('resetBrightness');
    } catch (_) {}
  }
}
