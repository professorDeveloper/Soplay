import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'cf_bypass_service.dart';

/// Catches `428 cfChallenge` responses, solves the Cloudflare challenge in
/// a hidden WebView, POSTs the cookies back to the backend so every later
/// call goes straight through, then transparently retries the original
/// request. From the caller's perspective the round-trip just took a few
/// extra seconds.
///
/// Pattern mirrors [AuthInterceptor]'s 401 → refresh → retry flow.
class CfBypassInterceptor extends Interceptor {
  static const String _skipKey = 'skipCfBypassInterceptor';
  static const String _retriedKey = 'cfBypassRetried';
  static const String _tag = '[CF]';

  final Dio dio;
  final CfBypassService service;

  CfBypassInterceptor({required this.dio, required this.service});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (request.extra[_skipKey] == true || request.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }

    if (err.response?.statusCode != 428) {
      handler.next(err);
      return;
    }

    final body = _decodeBody(err.response?.data);
    if (body == null || body['cfChallenge'] != true) {
      debugPrint('$_tag 428 received but body is not a CF challenge: '
          '${err.response?.data}');
      handler.next(err);
      return;
    }

    final host = (body['host'] as String?)?.trim();
    final url  = (body['url']  as String?)?.trim();
    final ua   = (body['userAgent'] as String?)?.trim() ??
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
    if (host == null || host.isEmpty || url == null || url.isEmpty) {
      debugPrint('$_tag bad CF challenge body: host=$host url=$url');
      handler.next(err);
      return;
    }

    debugPrint('$_tag solving CF challenge for $host …');
    final cookieHeader = await service.solve(host: host, url: url, userAgent: ua);
    if (cookieHeader == null) {
      debugPrint('$_tag CF solve TIMED OUT for $host');
      handler.next(err);
      return;
    }
    debugPrint('$_tag CF solved for $host (${cookieHeader.length} bytes of cookies)');

    try {
      await dio.post(
        '/cf-cookies',
        data: {
          'host': host,
          'cookies': cookieHeader,
          'userAgent': ua,
        },
        options: Options(extra: const {_skipKey: true}),
      );
    } catch (e) {
      debugPrint('$_tag POST /cf-cookies failed: $e');
      handler.next(err);
      return;
    }

    request.extra[_retriedKey] = true;
    try {
      debugPrint('$_tag retrying ${request.method} ${request.path}');
      final retry = await dio.fetch(request);
      handler.resolve(retry);
    } on DioException catch (e) {
      debugPrint('$_tag retry failed: ${e.response?.statusCode} ${e.message}');
      handler.next(e);
    } catch (e) {
      debugPrint('$_tag retry threw unexpected: $e');
      handler.next(err);
    }
  }

  /// Dio occasionally hands the body back as a raw `String` when the
  /// response transformer didn't fire (e.g. when `validateStatus` short-
  /// circuits inside an interceptor chain). Be defensive about both.
  Map<String, dynamic>? _decodeBody(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }
}
