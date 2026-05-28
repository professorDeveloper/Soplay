import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Solves a Cloudflare managed challenge inside a hidden WebView and returns
/// the `Cookie` header string ready to be sent to the backend.
///
/// Backend signals a CF challenge via HTTP 428 + body
/// `{ cfChallenge: true, host, url, userAgent }`. The interceptor calls
/// [solve] with those fields; if a non-null cookie string comes back, it
/// POSTs to `/api/cf-cookies` and retries the original request.
///
/// Mirrors `CloudflareKiller.kt` from CloudStream but stays on the client —
/// only this device runs the JS challenge; the cookies are then shared with
/// the backend so every subsequent provider call goes straight through.
class CfBypassService {
  static const _pollInterval = Duration(milliseconds: 600);
  static const _defaultTimeout = Duration(seconds: 30);

  /// Single-flight per host so concurrent 428s don't open 5 WebViews.
  final Map<String, Future<String?>> _inflight = {};

  /// Runs a [HeadlessInAppWebView] against the challenged URL until the
  /// `cf_clearance` cookie appears in the [CookieManager], then collects all
  /// cookies for that host into a `Cookie` header string.
  ///
  /// Returns `null` on timeout.
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
        // CF inspects various surface flags — leaving defaults gets us closest
        // to a real Chrome.
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
        // keep polling — getCookies can throw transiently right after start
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
