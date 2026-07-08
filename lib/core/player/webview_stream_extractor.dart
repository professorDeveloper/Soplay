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
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  static const _antiDebuggerShim = r'''
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
    var origSetInt = window.setInterval;
    window.setInterval = function(fn){
      try {
        var src = (typeof fn === 'function') ? fn.toString() : String(fn);
        if (src.indexOf('debugger') !== -1) return 0;
      } catch (_) {}
      return origSetInt.apply(window, arguments);
    };
    var RealFunction = window.Function;
    var SafeFunction = function() {
      try { return RealFunction.apply(this, arguments); }
      catch (e) { return function(){}; }
    };
    SafeFunction.prototype = RealFunction.prototype;
    try { window.Function = SafeFunction; } catch (_) {}
    var origEval = window.eval;
    window.eval = function(src) {
      try { return origEval.call(window, src); } catch (e) { return undefined; }
    };
    window.addEventListener('error', function(e){
      if (e && e.message && /Unexpected token|SyntaxError/i.test(e.message)) {
        try { e.preventDefault(); e.stopImmediatePropagation(); } catch (_) {}
        return true;
      }
    }, true);
  } catch (_) {}
})();
''';

  // ignore: unnecessary_string_escapes  // backslashes are JS-regex chars
  static String _xhrCaptureShim(List<String> hostFragments, List<String> urlPatterns) {
    final hosts = hostFragments.map((h) => "'$h'").join(',');
    final patterns = urlPatterns.map((p) => "'${p.toLowerCase()}'").join(',');
    return '''
(function(){
  var __hostFrags = [$hosts];
  var __urlPats   = [$patterns];

  function __matchHost(url) {
    try {
      var u = (typeof URL === 'function') ? new URL(url, location.href) : null;
      var host = u ? u.host.toLowerCase() : '';
      return __hostFrags.some(function(frag){
        var f = frag.toLowerCase().replace(/^\\*\\./, '');
        return host === f || host.indexOf('.' + f) > 0 || host.indexOf(f) >= 0;
      });
    } catch (_) { return false; }
  }
  function __matchPat(url) {
    var l = String(url).toLowerCase();
    return __urlPats.some(function(p){ return l.indexOf(p) !== -1; });
  }
  function __report(url, headers) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('streamCaptured', url, headers || {});
      }
    } catch (_) {}
  }

  // XMLHttpRequest hook
  try {
    var XOpen = XMLHttpRequest.prototype.open;
    var XSet  = XMLHttpRequest.prototype.setRequestHeader;
    var XSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
      try { this.__url = url; this.__hdrs = {}; } catch (_) {}
      return XOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
      try { if (this.__hdrs) this.__hdrs[name] = String(value); } catch (_) {}
      return XSet.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function() {
      try {
        var u = this.__url || '';
        if (u && __matchHost(u) && __matchPat(u)) {
          var abs = u;
          try { abs = new URL(u, location.href).toString(); } catch (_) {}
          __report(abs, this.__hdrs || {});
          // CRITICAL: do NOT call XSend — uzdown.space tokens (X-Match)
          // are single-use. Letting the WebView's XHR actually go through
          // consumes the token, leaving ExoPlayer's later request to 403.
          // We've captured URL + headers — that's all we need.
          return;
        }
      } catch (_) {}
      return XSend.apply(this, arguments);
    };
  } catch (_) {}

  // fetch() hook
  try {
    if (window.fetch) {
      var origFetch = window.fetch;
      window.fetch = function(input, init) {
        try {
          var url = (typeof input === 'string') ? input : (input && input.url) || '';
          if (url && __matchHost(url) && __matchPat(url)) {
            var hdrs = {};
            var initHdrs = (init && init.headers) || (input && input.headers);
            if (initHdrs) {
              if (typeof initHdrs.forEach === 'function') {
                initHdrs.forEach(function(v, k){ hdrs[k] = String(v); });
              } else if (typeof initHdrs === 'object') {
                Object.keys(initHdrs).forEach(function(k){ hdrs[k] = String(initHdrs[k]); });
              }
            }
            var abs = url;
            try { abs = new URL(url, location.href).toString(); } catch (_) {}
            __report(abs, hdrs);
            // CRITICAL: don't actually fetch — preserve the one-shot token.
            return new Promise(function(){});  // pending forever; WebView dies soon
          }
        } catch (_) {}
        return origFetch.apply(this, arguments);
      };
    }
  } catch (_) {}
})();
''';
  }

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

    void completeWith(String url, Map<String, dynamic> rawHeaders) {
      if (captured) return;
      captured = true;
      final headers = <String, String>{};
      rawHeaders.forEach((k, v) {
        if (v == null || k.isEmpty) return;
        final keep = config.captureHeaders.any((h) => h.toLowerCase() == k.toLowerCase()) ||
            k.toLowerCase().startsWith('x-');
        if (keep) headers[k] = v.toString();
      });
      pageHeaders.forEach((k, v) {
        if (!headers.keys.any((e) => e.toLowerCase() == k.toLowerCase())) {
          headers[k] = v;
        }
      });
      headers.putIfAbsent('User-Agent', () => userAgent);
      headers.putIfAbsent('Referer', () => 'https://${Uri.parse(pageUrl).host}/');
      headers.putIfAbsent('Origin', () => 'https://${Uri.parse(pageUrl).host}');

      if (kDebugMode) {
        debugPrint('[WebViewExtractor] captured $url headers=$headers');
      }
      if (!completer.isCompleted) {
        completer.complete(
          ExtractedStream(url: url, headers: headers, playType: config.playType),
        );
      }
      Timer(Duration.zero, stop);
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
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        blockNetworkImage: true,
        loadsImagesAutomatically: false,
        thirdPartyCookiesEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportZoom: false,
      ),
      onWebViewCreated: (controller) async {
        try {
          await controller.addUserScript(
            userScript: UserScript(
              source: _antiDebuggerShim,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          );
          await controller.addUserScript(
            userScript: UserScript(
              source: _xhrCaptureShim(
                [config.hostPattern],
                config.urlPatterns,
              ),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          );
          controller.addJavaScriptHandler(
            handlerName: 'streamCaptured',
            callback: (args) {
              if (args.isEmpty) return null;
              final url = args[0]?.toString() ?? '';
              if (url.isEmpty) return null;
              final headers = (args.length > 1 && args[1] is Map)
                  ? Map<String, dynamic>.from(args[1] as Map)
                  : <String, dynamic>{};
              completeWith(url, headers);
              return null;
            },
          );
        } catch (_) {}
      },
      shouldInterceptRequest: (controller, request) async {
        final uri = request.url;
        final urlStr = uri.toString();
        final lowerUrl = urlStr.toLowerCase();

        if (_matchHost(uri.host, config.hostPattern) &&
            config.urlPatterns.any((p) => lowerUrl.contains(p.toLowerCase()))) {
          if (!captured) {
            final hdrs = <String, dynamic>{};
            (request.headers ?? const {}).forEach((k, v) => hdrs[k] = v);
            completeWith(urlStr, hdrs);
          }
          return WebResourceResponse(
            contentType: 'text/plain',
            statusCode: 200,
            reasonPhrase: 'OK',
            headers: const {},
            data: Uint8List(0),
          );
        }

        if (_blockHostFragments.any((frag) => lowerUrl.contains(frag))) {
          return WebResourceResponse(
            contentType: 'text/plain',
            statusCode: 200,
            reasonPhrase: 'OK',
            headers: const {},
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
