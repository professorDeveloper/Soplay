import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:soplay/core/js/js_log.dart';
import 'package:soplay/core/system/webview_env.dart';

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
    final sw = Stopwatch()..start();
    final completer = Completer<String?>();
    Timer? poll;
    Timer? watchdog;
    Timer? retarget;
    InAppWebViewController? controller;

    // Cloudflare scopes cf_clearance to the whole zone, so the challenge on any
    // page of a host clears every other page of it.
    final origin = 'https://$host/';

    // Drop whatever clearance is already in the jar before solving.
    //
    // Not a precaution — the poll below completes on the mere PRESENCE of a
    // cf_clearance cookie, so a stale one short-circuits the whole solve. That
    // is what animepahe.pw did: the first poll tick fires at 600ms and the log
    // read `solved animepahe.pw (607ms)`, which is far too fast for a managed
    // challenge to have been answered. The service was reporting success on a
    // cookie from an earlier run, the replay was rejected exactly like the
    // request that triggered the solve, and with allowCfRetry already spent the
    // extractor was handed the challenge page — getHome() then sat until its
    // 60s timeout and the home screen stayed empty.
    //
    // Deleting it costs nothing, because reaching this method means a request
    // just came back challenged: any clearance still present has already been
    // proven not to work. Clearing it is what makes the poll's "found a cookie"
    // mean "the WebView earned one just now".
    try {
      final cm = CookieManager.instance();
      for (final u in {WebUri(origin), WebUri(url)}) {
        await cm.deleteCookie(url: u, name: 'cf_clearance');
        await cm.deleteCookie(url: u, name: 'cf_clearance', domain: '.$host');
      }
    } catch (_) {
      // A jar we cannot prune still solves correctly whenever the stale cookie
      // has expired on its own; failing the solve outright would be worse.
    }

    final headless = HeadlessInAppWebView(
      webViewEnvironment: await WebViewEnv.ensure(),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        useShouldInterceptRequest: false,
      ),
      onWebViewCreated: (c) => controller = c,
    );

    Future<void> stop() async {
      poll?.cancel();
      watchdog?.cancel();
      retarget?.cancel();
      try { await headless.dispose(); } catch (_) {}
    }

    // The failing request is often an API endpoint, and a challenge served for
    // one is a document the WebView renders, but the page it lands on after
    // solving is raw JSON — which Android hands to the download manager instead
    // of loading, aborting the navigation partway through the flow. Half a
    // budget in, fall back to the host root: it is an ordinary HTML page, it
    // carries the same zone-wide challenge, and the clearance it earns is the
    // one the original request needed. Costs nothing when the first target
    // works, because this timer never fires.
    if (url != origin) {
      retarget = Timer(timeout ~/ 2, () async {
        if (completer.isCompleted) return;
        JsLog.info('cf', 'retargeting $host solve to the site root');
        try {
          await controller?.loadUrl(urlRequest: URLRequest(url: WebUri(origin)));
        } catch (_) {}
      });
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
        if (!completer.isCompleted) {
          JsLog.res('cf', 'solved $host', ms: sw.elapsedMilliseconds);
          completer.complete(header);
        }
        await stop();
      } catch (_) {
      }
    });

    watchdog = Timer(timeout, () async {
      if (!completer.isCompleted) {
        JsLog.err('cf', 'no cf_clearance for $host after ${timeout.inSeconds}s');
        completer.complete(null);
      }
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
