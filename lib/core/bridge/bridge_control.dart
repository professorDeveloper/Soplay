import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Controls the on-device HTTP bridge (Android only) that shares this phone's
/// CloudStream / Aniyomi / Manga sources with the Sozo **desktop** app on the
/// same Wi‑Fi. The desktop is the client (see [ExtensionBridge]); the phone is
/// the host.
class BridgeControl {
  BridgeControl._();

  static const MethodChannel _ch = MethodChannel('soplay/bridge');

  /// Only Android can host the sources (it runs the real DEX plugins).
  static bool get canHost => Platform.isAndroid;

  static Future<BridgeStatus> getStatus() async {
    if (!canHost) return const BridgeStatus(enabled: false, link: null);
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getStatus');
      return BridgeStatus.fromMap(m);
    } catch (_) {
      return const BridgeStatus(enabled: false, link: null);
    }
  }

  static Future<BridgeStatus> setEnabled(bool enabled) async {
    if (!canHost) return const BridgeStatus(enabled: false, link: null);
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
        'setEnabled',
        {'enabled': enabled},
      );
      return BridgeStatus.fromMap(m);
    } catch (_) {
      return const BridgeStatus(enabled: false, link: null);
    }
  }
}

class BridgeStatus {
  const BridgeStatus({required this.enabled, required this.link});

  final bool enabled;

  /// `http://<phone-lan-ip>:8765` when running, else null.
  final String? link;

  factory BridgeStatus.fromMap(Map<String, dynamic>? m) => BridgeStatus(
        enabled: m?['enabled'] == true,
        link: m?['link'] as String?,
      );
}
