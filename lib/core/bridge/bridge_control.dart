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

  /// Which providers the phone currently shares with the desktop. `shareAll`
  /// (the default) exposes every provider; otherwise only [SharedSelection.ids].
  static Future<SharedSelection> getSharedProviders() async {
    if (!canHost) return const SharedSelection(shareAll: true, ids: {});
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getSharedProviders');
      return SharedSelection.fromMap(m);
    } catch (_) {
      return const SharedSelection(shareAll: true, ids: {});
    }
  }

  /// Persist the share selection. When [shareAll] is true the phone serves every
  /// provider (and [ids] is ignored); otherwise only [ids] are exposed.
  static Future<SharedSelection> setSharedProviders({
    required bool shareAll,
    required Set<String> ids,
  }) async {
    if (!canHost) return const SharedSelection(shareAll: true, ids: {});
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
        'setSharedProviders',
        {'shareAll': shareAll, 'ids': ids.toList()},
      );
      return SharedSelection.fromMap(m);
    } catch (_) {
      return SharedSelection(shareAll: shareAll, ids: ids);
    }
  }
}

/// The phone's current share selection, mirroring the native `sozo_bridge`
/// prefs. [shareAll] true → every provider is shared; else only [ids].
class SharedSelection {
  const SharedSelection({required this.shareAll, required this.ids});

  final bool shareAll;
  final Set<String> ids;

  factory SharedSelection.fromMap(Map<String, dynamic>? m) => SharedSelection(
        shareAll: m?['shareAll'] != false,
        ids: ((m?['ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet(),
      );
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
