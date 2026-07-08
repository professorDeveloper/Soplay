import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class CfBypassService {
  static const _pollInterval = Duration(milliseconds: 600);
  static const _defaultTimeout = Duration(seconds: 30);

  final Map<String, Future<String?>> _inflight = {};

  Future<String?> solve({
    required String host,
    required String url,
    required String userAgent,
    Duration timeout = _defaultTimeout,
  }) {
    final existing = _inflight[host];
    if (existing != null) return existing;
    final future = _runSolve(host: host, url: url, userAgent: userAgent, timeout: timeout)
        .whenComplete(() => _inflight.remove(host));
    _inflight[host] = future;
    return future;
  }

  Future<String?> _runSolve({
    required String host,
    required String url,
    required String userAgent,
    required Duration timeout,
  }) async {
    final completer = Completer<String?>();
    Timer? poll;
    Timer? watchdog;

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        useShouldInterceptRequest: false,
      ),
    );

    Future<void> stop() async {
      poll?.cancel();
      watchdog?.cancel();
      try { await headless.dispose(); } catch (_) {}
    }

    poll = Timer.periodic(_pollInterval, (_) async {
      try {
        final cookies = await CookieManager.instance()
            .getCookies(url: WebUri('https://$host/'));
        final hasClearance = cookies.any(
          (c) => c.name == 'cf_clearance' && '${c.value}'.isNotEmpty,
        );
        if (!hasClearance) return;

        final header = cookies
            .where((c) => '${c.value}'.isNotEmpty)
            .map((c) => '${c.name}=${c.value}')
            .join('; ');
        if (!completer.isCompleted) completer.complete(header);
        await stop();
      } catch (_) {
      }
    });

    watchdog = Timer(timeout, () async {
      if (!completer.isCompleted) completer.complete(null);
      await stop();
    });

    try {
      await headless.run();
    } catch (e) {
      if (!completer.isCompleted) completer.complete(null);
      await stop();
    }

    return completer.future;
  }
}
