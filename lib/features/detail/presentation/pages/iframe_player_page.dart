import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class IframePlayerArgs {
  final String url;
  final String title;
  final Map<String, String> headers;

  const IframePlayerArgs({
    required this.url,
    this.title = '',
    this.headers = const {},
  });
}

/// Fullscreen WebView player for providers that sign every CDN request
/// in-page (uzmovi). The page renders its own videojs player and we strip
/// the surrounding site UI with injected CSS so the experience is
/// player-only — closer to the native ExoPlayer screen than a normal
/// in-app browser would be.
class IframePlayerPage extends StatefulWidget {
  final IframePlayerArgs args;
  const IframePlayerPage({super.key, required this.args});

  @override
  State<IframePlayerPage> createState() => _IframePlayerPageState();
}

class _IframePlayerPageState extends State<IframePlayerPage> {
  bool _loading = true;
  bool _showOverlay = true;
  Timer? _overlayTimer;

  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  // Strips the uzmovi site chrome and expands the videojs player to fill
  // the viewport. Re-applies on each load for SPA-style navigation.
  static const _playerOnlyCss = '''
    html, body { margin:0!important; padding:0!important; background:#000!important; overflow:hidden!important; height:100vh!important; }
    body * { visibility:hidden!important; }
    .video-js, .video-js *, video, video * { visibility:visible!important; }
    .video-js, video { position:fixed!important; top:0!important; left:0!important; right:0!important; bottom:0!important;
                       width:100vw!important; height:100vh!important; z-index:9999!important; background:#000!important; }
    /* Allow the page's "Tomosha" / episode-picker buttons to stay tappable */
    .batcoh-list, .batcoh-list *, .batcoh-item, .episode-list, .episode-list * { visibility:visible!important; }
    .batcoh-list { position:fixed!important; bottom:0!important; left:0!important; right:0!important;
                   background:rgba(0,0,0,0.85)!important; padding:8px!important; z-index:10000!important;
                   overflow-x:auto!important; white-space:nowrap!important; max-height:60px!important; }
    .batcoh-item { display:inline-block!important; margin:4px!important; padding:6px 10px!important;
                   background:#333!important; color:#fff!important; text-decoration:none!important; border-radius:4px!important; }
    /* Block common ad/banner containers */
    .adsbygoogle, .ad, .ads, .ad-banner, [id^="google_ads_"], [id*="banner"] { display:none!important; }
  ''';

  static const _hideChromeJs = '''
    (function(){
      function apply() {
        try {
          var s = document.getElementById('__so_player_css');
          if (!s) {
            s = document.createElement('style');
            s.id = '__so_player_css';
            s.innerHTML = `$_playerOnlyCss`;
            (document.head || document.documentElement).appendChild(s);
          }
        } catch (e) {}
      }
      apply();
      // Re-apply periodically — the page's JS may inject more chrome after load.
      setInterval(apply, 1500);
    })();
  ''';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _scheduleOverlayHide();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WakelockPlus.disable();
    super.dispose();
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _showOverlayBriefly() {
    setState(() => _showOverlay = true);
    _scheduleOverlayHide();
  }

  @override
  Widget build(BuildContext context) {
    final referer = widget.args.headers['Referer'];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false, bottom: false, left: false, right: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _showOverlayBriefly,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.args.url),
                  headers: referer != null ? {'Referer': referer} : null,
                ),
                initialSettings: InAppWebViewSettings(
                  userAgent: _mobileUserAgent,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  cacheEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  thirdPartyCookiesEnabled: true,
                  supportZoom: false,
                  transparentBackground: true,
                ),
                onLoadStart: (c, _) {
                  setState(() => _loading = true);
                },
                onLoadStop: (c, _) async {
                  try {
                    await c.evaluateJavascript(source: _hideChromeJs);
                  } catch (_) {}
                  if (mounted) setState(() => _loading = false);
                },
                onConsoleMessage: (c, msg) {
                  // ignore noisy console errors from the page
                },
              ),
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_showOverlay)
                Positioned(
                  top: 16, left: 16,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
