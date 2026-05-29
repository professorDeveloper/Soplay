import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:soplay/features/detail/domain/entities/extractor_config_entity.dart';

class ExtractedStream {
  final String url;
  final Map<String, String> headers;
  final String playType;

  const ExtractedStream({
    required this.url,
    required this.headers,
    required this.playType,
  });
}

class WebViewStreamExtractor {
  // Mobile Chrome UA — uzmovi/uzdown serve a mobile-optimized player
  // (`/live/.../mob hd/...`) that doesn't trip the desktop anti-debugger
  // chain in app.js that crashes InAppWebView's V8.
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  // Anti-anti-debugger shim. Obfuscated provider scripts (e.g. uzmovi's
  // app.js) probe Function.prototype.toString and console.debug to detect
  // dev tools / tampering, then SyntaxError-out on purpose. We replace the
  // markers with benign no-ops BEFORE any other script runs, so the
  // obfuscator's self-check passes and the real player init proceeds.
  static const _antiDebuggerShim = '''
(function(){
  try {
    var origToString = Function.prototype.toString;
    Function.prototype.toString = function() {
      try { return origToString.call(this); } catch (_) { return 'function () { [native code] }'; }
    };
    if (window.console) {
      var noop = function(){};
      ['debug','clear','dir','dirxml','profile','profileEnd'].forEach(function(k){
        try { window.console[k] = noop; } catch (_) {}
      });
    }
    // Some obfuscators run a tight setInterval(debugger;) loop; mask it.
    var origSetInt = window.setInterval;
    window.setInterval = function(fn, ms){
      try {
        var src = (typeof fn === 'function') ? fn.toString() : String(fn);
        if (src.indexOf('debugger') !== -1) return 0;
      } catch (_) {}
      return origSetInt.apply(window, arguments);
    };
  } catch (_) {}
})();
''';

  // Third-party trackers / ad providers that drag the page down or throw
  // (videojs CDN, yandex, ok.ru, vk, google analytics). The actual stream
  // load doesn't need any of them — blocking speeds up extraction and
  // avoids unrelated console errors.
  static final _blockHostFragments = <String>[
    'mc.yandex.ru',
    'yastatic.net',
    'yandex.net',
    'connect.ok.ru',
    'st-ok.cdn-vk.ru',
    'vk.com',
    'googletagmanager.com',
    'google-analytics.com',
    'doubleclick.net',
    'googleads.g.doubleclick',
    'googlesyndication.com',
    'youtube.com/log',
    'cdn.jsdelivr.net/npm/videojs-contrib-ads',
    'cdn.jsdelivr.net/npm/videojs-vast-vpaid',
  ];

  Future<ExtractedStream?> extract({
    required String pageUrl,
    required ExtractorConfigEntity config,
    Map<String, String> pageHeaders = const {},
  }) async {
    final completer = Completer<ExtractedStream?>();
    Timer? watchdog;
    HeadlessInAppWebView? headless;
    var captured = false;

    // Always use mobile UA for the WebView, regardless of what the backend
    // provides (backend's UA is for its own HTTP fetches and is usually
    // desktop). Mobile UA → mobile player path that runs cleanly here.
    final userAgent = _mobileUserAgent;
    final referer = _headerValue(pageHeaders, 'Referer');

    if (kDebugMode) {
      debugPrint(
        '[WebViewExtractor] start page=$pageUrl host=${config.hostPattern} '
        'patterns=${config.urlPatterns} timeout=${config.timeoutMs}ms',
      );
    }

    Future<void> stop() async {
      watchdog?.cancel();
      try {
        await headless?.dispose();
      } catch (_) {}
    }

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(pageUrl),
        headers: referer != null ? {'Referer': referer} : null,
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        useShouldInterceptRequest: true,
        // Allow the embed page to load CDN sub-resources over HTTP if any.
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        // Faster load; Lite-Mode for headless extraction.
        blockNetworkImage: true,
        loadsImagesAutomatically: false,
        thirdPartyCookiesEnabled: true,
      ),
      onWebViewCreated: (controller) async {
        // Persist cookies across uses so the user only logs in once.
        try {
          await CookieManager.instance().setCookie(
            url: WebUri('https://uzmovi.net/'),
            name: '_ws_warmup',
            value: '1',
          );
        } catch (_) {}
      },
      onLoadStart: (controller, _) async {
        // Inject the anti-debugger shim as early as possible so the
        // obfuscated app.js sees a "tampered" environment that it
        // accepts as legitimate.
        try {
          await controller.evaluateJavascript(source: _antiDebuggerShim);
        } catch (_) {}
      },
      shouldInterceptRequest: (controller, request) async {
        final uri = request.url;
        final urlStr = uri.toString();
        final lowerUrl = urlStr.toLowerCase();

        // Capture the stream first — match host + url patterns.
        if (!captured && _matchHost(uri.host, config.hostPattern)) {
          if (config.urlPatterns.any((p) => lowerUrl.contains(p.toLowerCase()))) {
            captured = true;
            final headers = <String, String>{};
            (request.headers ?? const {}).forEach((k, v) {
              if (config.captureHeaders.any((h) => h.toLowerCase() == k.toLowerCase())) {
                headers[k] = v;
              }
            });
            pageHeaders.forEach((k, v) {
              if (!headers.keys.any((e) => e.toLowerCase() == k.toLowerCase())) {
                headers[k] = v;
              }
            });

            if (kDebugMode) {
              debugPrint('[WebViewExtractor] captured $urlStr headers=$headers');
            }
            if (!completer.isCompleted) {
              completer.complete(
                ExtractedStream(
                  url: urlStr,
                  headers: headers,
                  playType: config.playType,
                ),
              );
            }
            Timer(Duration.zero, stop);
            return null;
          }
        }

        // Drop noisy third-party requests that aren't needed for stream
        // resolution and that often error out under WebView's V8.
        if (_blockHostFragments.any((frag) => lowerUrl.contains(frag))) {
          return WebResourceResponse(
            contentType: 'text/plain',
            statusCode: 200,
            reasonPhrase: 'OK',
            data: Uint8List(0),
          );
        }

        return null;
      },
      onConsoleMessage: (controller, msg) {
        if (kDebugMode) {
          final lvl = msg.messageLevel.toString().split('.').last;
          debugPrint('[WebViewExtractor:console:$lvl] ${msg.message}');
        }
      },
    );

    watchdog = Timer(Duration(milliseconds: config.timeoutMs), () async {
      if (kDebugMode && !completer.isCompleted) {
        debugPrint('[WebViewExtractor] timeout — no matching request captured');
      }
      if (!completer.isCompleted) completer.complete(null);
      await stop();
    });

    try {
      await headless.run();
    } catch (e) {
      if (kDebugMode) debugPrint('[WebViewExtractor] run failed: $e');
      if (!completer.isCompleted) completer.complete(null);
      await stop();
    }

    return completer.future;
  }

  static String? _headerValue(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase() && entry.value.isNotEmpty) {
        return entry.value;
      }
    }
    return null;
  }

  bool _matchHost(String host, String pattern) {
    final h = host.toLowerCase();
    final p = pattern.toLowerCase();
    if (!p.contains('*')) return h == p;
    final suffix = p.replaceFirst('*.', '');
    return h == suffix || h.endsWith('.$suffix');
  }
}
