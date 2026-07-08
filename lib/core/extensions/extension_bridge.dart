import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ExtensionBridge {
  ExtensionBridge._();
  static final ExtensionBridge instance = ExtensionBridge._();

  static String? _override;

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

  static bool get isEnabled => !Platform.isAndroid && baseUrl.isNotEmpty;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.plain,
    ),
  );

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
