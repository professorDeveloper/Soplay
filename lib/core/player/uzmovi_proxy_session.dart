import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// One long-lived hidden WebView per uzmovi page.
///
/// The page's own JS computes per-request X-* signatures, so any request to
/// `*.uzdown.space` must go through it. This session keeps the WebView alive,
/// exposes [fetchSigned] which proxies arbitrary URLs through the page's JS
/// `fetch()` (so signing happens automatically), and exposes [fetchEpisodes]
/// for serial pages (DOM scrape after JS render).
///
/// Memory-conscious: only one session per page; [dispose] kills the WebView.
class UzmoviProxySession {
  final String pageUrl;
  final Map<String, String> pageHeaders;
  final int timeoutMs;

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  final _readyCompleter = Completer<void>();
  bool _disposed = false;

  // In-flight bridge calls keyed by request id.
  final Map<String, Completer<BridgeResponse>> _pending = {};
  int _seq = 0;

  // Serialize fetches: the page's signing wrapper holds per-instance state
  // (rotating nonces/counters) and parallel requests cause it to emit invalid
  // X-Match values → 403. We process one fetchSigned at a time.
  final List<Completer<void>> _fetchQueue = [];
  bool _fetchBusy = false;

  UzmoviProxySession({
    required this.pageUrl,
    this.pageHeaders = const {},
    this.timeoutMs = 30000,
  });

  bool get isReady => _readyCompleter.isCompleted && !_disposed;

  /// Boots the WebView, loads the page, installs the JS bridge.
  /// Completes when the bridge is ready to accept fetch calls.
  Future<void> start() async {
    if (_headless != null) return _readyCompleter.future;

    final ua = pageHeaders['User-Agent'] ??
        'Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
    final referer = pageHeaders['Referer'];

    _headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(pageUrl),
        headers: referer != null ? {'Referer': referer} : null,
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: ua,
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
      ),
      onWebViewCreated: (controller) async {
        _controller = controller;
        try {
          await controller.addUserScript(
            userScript: UserScript(
              source: _antiDebuggerShim,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          );
          await controller.addUserScript(
            userScript: UserScript(
              source: _bridgeShim,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          );
          // Bridge → Dart handlers.
          controller.addJavaScriptHandler(
            handlerName: '__uzbridgeReady',
            callback: (args) {
              if (!_readyCompleter.isCompleted) _readyCompleter.complete();
              return null;
            },
          );
          controller.addJavaScriptHandler(
            handlerName: '__uzbridgeResponse',
            callback: (args) {
              if (args.isEmpty) return null;
              final id = args[0]?.toString() ?? '';
              final completer = _pending.remove(id);
              if (completer == null) return null;
              final ok = args.length > 1 ? args[1] == true : false;
              if (!ok) {
                final err = args.length > 2 ? args[2]?.toString() ?? 'bridge error' : 'bridge error';
                completer.complete(BridgeResponse.error(err));
              } else {
                final status = (args.length > 2 ? args[2] : 200) as int? ?? 200;
                final contentType = args.length > 3 ? args[3]?.toString() ?? '' : '';
                final bodyB64 = args.length > 4 ? args[4]?.toString() ?? '' : '';
                final body = bodyB64.isEmpty ? Uint8List(0) : base64Decode(bodyB64);
                completer.complete(BridgeResponse.ok(status, contentType, body));
              }
              return null;
            },
          );
        } catch (e, st) {
          if (kDebugMode) debugPrint('[UzSession] onCreate failed: $e\n$st');
        }
      },
      shouldInterceptRequest: (controller, request) async {
        // Block trackers / ads to keep the page light.
        final urlStr = request.url.toString().toLowerCase();
        if (_blockFragments.any((f) => urlStr.contains(f))) {
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
          debugPrint('[UzSession:console:$lvl] ${msg.message}');
        }
      },
    );

    try {
      await _headless!.run();
    } catch (e) {
      if (!_readyCompleter.isCompleted) _readyCompleter.completeError(e);
      rethrow;
    }

    // Watchdog: if the bridge never reports ready within timeoutMs, fail.
    Timer(Duration(milliseconds: timeoutMs), () {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(
          TimeoutException('UzmoviProxySession failed to bootstrap', Duration(milliseconds: timeoutMs)),
        );
      }
    });

    return _readyCompleter.future;
  }

  /// Fetches a URL through the page's XHR (signing is automatic via the
  /// page's setRequestHeader wrapper). Serialized — one request at a time
  /// to avoid races in the page's signing state.
  Future<BridgeResponse> fetchSigned(String url) async {
    if (_disposed) return BridgeResponse.error('session disposed');
    if (!_readyCompleter.isCompleted) await _readyCompleter.future;

    // Queue: wait if another fetch is running.
    if (_fetchBusy) {
      final gate = Completer<void>();
      _fetchQueue.add(gate);
      await gate.future;
    }
    _fetchBusy = true;

    try {
      final id = (++_seq).toString();
      final completer = Completer<BridgeResponse>();
      _pending[id] = completer;

      final jsArg = jsonEncode({'id': id, 'url': url});
      try {
        await _controller!.evaluateJavascript(
          source: 'window.__uzFetch(${jsonEncode(jsArg)})',
        );
      } catch (e) {
        _pending.remove(id);
        return BridgeResponse.error('evaluate failed: $e');
      }

      return await completer.future.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () {
          _pending.remove(id);
          return BridgeResponse.error('fetch timeout');
        },
      );
    } finally {
      _fetchBusy = false;
      // Wake the next waiter if any.
      if (_fetchQueue.isNotEmpty) {
        final next = _fetchQueue.removeAt(0);
        if (!next.isCompleted) next.complete();
      }
    }
  }

  /// Returns `.batcoh-list` episode anchors rendered by the page's JS.
  /// Each entry: { href, label }.
  Future<List<Map<String, String>>> fetchEpisodes() async {
    if (!_readyCompleter.isCompleted) await _readyCompleter.future;
    try {
      final result = await _controller!.evaluateJavascript(source: r'''
        (function(){
          var out = [];
          var els = document.querySelectorAll('.batcoh-list a.batcoh-item, .batcoh-list a[href*="/episode/"]');
          for (var i = 0; i < els.length; i++) {
            var a = els[i];
            out.push({
              href: a.href || '',
              label: (a.getAttribute('title') || a.textContent || '').trim()
            });
          }
          return out;
        })()
      ''');
      if (result is! List) return [];
      return result
          .whereType<Map>()
          .map((m) => {
                'href':  (m['href']  ?? '').toString(),
                'label': (m['label'] ?? '').toString(),
              })
          .where((e) => (e['href'] ?? '').isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[UzSession] fetchEpisodes failed: $e');
      return [];
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(BridgeResponse.error('disposed'));
    }
    _pending.clear();
    for (final g in _fetchQueue) {
      if (!g.isCompleted) g.complete();
    }
    _fetchQueue.clear();
    _fetchBusy = false;
    try {
      await _headless?.dispose();
    } catch (_) {}
    _headless = null;
    _controller = null;
  }

  // ── shims ────────────────────────────────────────────────────────────

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

  // Bridge: window.__uzFetch({id, url}) → uses XMLHttpRequest (not fetch),
  // because the page's player wraps XMLHttpRequest.prototype to inject the
  // X-ATT-DeviceId/X-Match/X-Path signing headers per URL. Our XHR therefore
  // inherits that signing for free. fetch() would bypass the wrapper.
  //
  // We delay the actual XHR send until the next tick so anti-debugger code in
  // app.js has time to install its XHR wrapper before we run.
  static const _bridgeShim = r'''
(function(){
  function toBase64(buffer) {
    var bytes = new Uint8Array(buffer);
    var bin = '';
    var chunk = 8192;
    for (var i = 0; i < bytes.length; i += chunk) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(bin);
  }

  function reply(id, ok, status, contentType, bodyB64) {
    try {
      window.flutter_inappwebview.callHandler(
        '__uzbridgeResponse', id, ok, status, contentType, bodyB64
      );
    } catch (e) {}
  }

  // Block page-initiated uzdown.space XHRs (videojs in our session WebView
  // would otherwise eat the signing wrapper's tokens in parallel with us).
  // Our own bridge XHRs are tagged with __bridge=true and pass through.
  try {
    var OrigSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function() {
      try {
        if (!this.__bridge) {
          var u = (this.__url || this.responseURL || '');
          if (/uzdown\.[a-z]+/i.test(u)) {
            try { this.abort(); } catch (e) {}
            return;
          }
        }
      } catch (e) {}
      return OrigSend.apply(this, arguments);
    };
    var OrigOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      try { this.__url = url; } catch (e) {}
      return OrigOpen.apply(this, arguments);
    };
  } catch (e) {}

  // Also kill any auto-playing <video> elements so the page's player
  // doesn't try to keep buffering segments while we work.
  try {
    setInterval(function(){
      var vs = document.querySelectorAll('video');
      for (var i = 0; i < vs.length; i++) {
        try { vs[i].pause(); vs[i].muted = true; } catch (e) {}
      }
    }, 500);
  } catch (e) {}

  window.__uzFetch = function(payload) {
    var p;
    try { p = (typeof payload === 'string') ? JSON.parse(payload) : payload; }
    catch (e) { p = {}; }
    var id  = p.id  || '';
    var url = p.url || '';
    if (!id || !url) return;
    try {
      var xhr = new XMLHttpRequest();
      xhr.__bridge = true;   // pass our gate
      xhr.open('GET', url, true);
      xhr.responseType = 'arraybuffer';
      try { xhr.setRequestHeader('Accept', '*/*'); } catch (e) {}
      xhr.onload = function() {
        var ct = '';
        try { ct = xhr.getResponseHeader('content-type') || ''; } catch (e) {}
        var b64 = '';
        try {
          var buf = xhr.response;
          if (buf && buf.byteLength != null) b64 = toBase64(buf);
        } catch (e) {}
        reply(id, true, xhr.status || 0, ct, b64);
      };
      xhr.onerror = function() {
        reply(id, false, 'xhr error: status=' + xhr.status);
      };
      xhr.onabort = function() {
        reply(id, false, 'xhr aborted');
      };
      xhr.send();
    } catch (e) {
      reply(id, false, 'sync error: ' + e);
    }
  };

  function signalReady() {
    try {
      window.flutter_inappwebview.callHandler('__uzbridgeReady');
    } catch (e) {}
  }
  // Wait a beat past DOMContentLoaded so app.js (which installs the XHR
  // signing wrapper) has actually run. Without this delay our early bridge
  // calls would use the raw XHR with no signing.
  function deferredReady() { setTimeout(signalReady, 1500); }
  if (document.readyState === 'complete') {
    deferredReady();
  } else if (document.readyState === 'interactive') {
    window.addEventListener('load', deferredReady);
  } else {
    document.addEventListener('DOMContentLoaded', function(){
      window.addEventListener('load', deferredReady);
    });
  }
})();
''';

  static final _blockFragments = <String>[
    'mc.yandex.ru', 'yastatic.net', 'yandex.net',
    'connect.ok.ru', 'st-ok.cdn-vk.ru', 'vk.com',
    'googletagmanager.com', 'google-analytics.com', 'doubleclick.net',
    'googleads.g.doubleclick', 'googlesyndication.com', 'youtube.com/log',
    'cdn.jsdelivr.net/npm/videojs-contrib-ads',
    'cdn.jsdelivr.net/npm/videojs-vast-vpaid',
  ];
}

class BridgeResponse {
  final bool ok;
  final int status;
  final String contentType;
  final Uint8List body;
  final String? error;

  BridgeResponse.ok(this.status, this.contentType, this.body)
      : ok = true, error = null;

  BridgeResponse.error(String err)
      : ok = false, status = 0, contentType = '', body = Uint8List(0), error = err;
}
