import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// HTTP client to the **local extension bridge** — the on-device CloudStream /
/// Aniyomi / Manga hosts, exposed over HTTP by the Android app's `BridgeServer`
/// when it runs on a local emulator or a connected device.
///
/// This is how the DEX-based extensions "work" on desktop: real Android (local)
/// runs the plugins; the Windows client just fetches the same JSON over HTTP.
///
/// Enabled on **non-Android** platforms only when `EXTENSION_BRIDGE_URL` is set
/// in `.env` (e.g. `http://127.0.0.1:8765`). Android keeps using the native
/// MethodChannel unchanged. When unset, every call is a no-op returning null, so
/// desktop behaves exactly as before (extensions simply don't appear).
class ExtensionBridge {
  ExtensionBridge._();
  static final ExtensionBridge instance = ExtensionBridge._();

  /// Runtime-set bridge URL (pasted by the user on the desktop app and stored in
  /// Hive). Takes precedence over the `.env` value. Set via [setUrl].
  static String? _override;

  /// Set the desktop bridge URL at runtime (from the "Desktop sources" screen).
  static void setUrl(String? url) {
    final v = (url ?? '').trim();
    _override = v.isEmpty ? null : v;
  }

  static String get baseUrl {
    final o = _override;
    if (o != null && o.isNotEmpty) return o;
    if (!dotenv.isInitialized) return '';
    return (dotenv.maybeGet('EXTENSION_BRIDGE_URL') ?? '').trim();
  }

  /// True when the bridge should be used: a non-Android platform with a URL set.
  static bool get isEnabled => !Platform.isAndroid && baseUrl.isNotEmpty;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.plain,
    ),
  );

  /// `GET <base>/<system>/<method>?<params>` → JSON body (or null on failure).
  /// [system] is `cloudstream` | `aniyomi` | `manga`; [method] and [params]
  /// mirror the MethodChannel call 1:1.
  Future<String?> call(
    String system,
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final base = baseUrl;
    if (base.isEmpty) return null;
    try {
      final resp = await _dio.get<String>(
        '$base/$system/$method',
        queryParameters: params?.map(
          (k, v) => MapEntry(k, v?.toString() ?? ''),
        ),
      );
      return resp.data;
    } catch (_) {
      return null;
    }
  }
}
