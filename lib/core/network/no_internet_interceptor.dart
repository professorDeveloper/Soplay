import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:soplay/core/router/app_router.dart';

class NoInternetInterceptor extends Interceptor {
  static int _lastRedirectMs = 0;
  static int _lastProbeMs = 0;
  static bool _lastProbeOnline = true;
  static Future<bool>? _inFlightProbe;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_looksOffline(err)) {
      unawaited(_maybeRedirect());
    }
    handler.next(err);
  }

  bool _looksOffline(DioException err) {
    if (err.type == DioExceptionType.cancel) return false;
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout) {
      return true;
    }
    final error = err.error;
    return error is SocketException;
  }

  Future<void> _maybeRedirect() async {
    final path = AppRouter.router.routeInformationProvider.value.uri.path;
    if (path == '/no-internet' || path == '/downloads') return;

    final online = await _probeInternet();
    if (online) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRedirectMs < 1200) return;
    _lastRedirectMs = now;

    final currentPath =
        AppRouter.router.routeInformationProvider.value.uri.path;
    if (currentPath == '/no-internet' || currentPath == '/downloads') return;

    scheduleMicrotask(() {
      AppRouter.router.go('/no-internet');
    });
  }

  Future<bool> _probeInternet() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProbeMs < 2000) {
      return Future.value(_lastProbeOnline);
    }
    final existing = _inFlightProbe;
    if (existing != null) return existing;
    final probe = _runProbe();
    _inFlightProbe = probe;
    probe.whenComplete(() {
      _inFlightProbe = null;
    });
    return probe;
  }

  Future<bool> _runProbe() async {
    bool online;
    try {
      final result = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 3));
      online = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      online = false;
    }
    _lastProbeMs = DateTime.now().millisecondsSinceEpoch;
    _lastProbeOnline = online;
    return online;
  }
}
