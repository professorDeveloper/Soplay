import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'extractor_entity.dart';

class ExtractorRunner {
  final Dio _dio;
  final Map<String, String> _jsCache = {};
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _webViewController;
  bool _runtimeLoaded = false;
  String? _runtimeJs;

  ExtractorRunner({required Dio dio}) : _dio = dio;

  Future<void> loadRuntime() async {
    if (_runtimeLoaded) return;
    final response = await _dio.get<String>(
      '/extractors/runtime',
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAuthInterceptor': true},
      ),
    );
    if (response.data != null) {
      _runtimeJs = response.data!;
      _runtimeLoaded = true;
      debugPrint('[ExtractorRunner] runtime loaded');
    }
  }

  Future<void> loadExtractor(ExtractorEntity extractor) async {
    if (_jsCache.containsKey(extractor.name)) return;
    final response = await _dio.get<String>(
      extractor.url,
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAuthInterceptor': true},
      ),
    );
    if (response.data != null) {
      _jsCache[extractor.name] = response.data!;
      debugPrint('[ExtractorRunner] loaded: ${extractor.name}');
    }
  }

  Future<Map<String, dynamic>> call(
    String extractorName,
    String method, [
    dynamic args,
  ]) async {
    if (!_runtimeLoaded || _runtimeJs == null) {
      throw Exception('Runtime not loaded. Call loadRuntime() first.');
    }

    final js = _jsCache[extractorName];
    if (js == null) {
      throw Exception('Extractor "$extractorName" not loaded');
    }

    final argsJson = args != null ? jsonEncode(args) : '{}';
    final script =
        '''
(async () => {
  try {
    $_runtimeJs
    $js
    const result = await Provider.$method($argsJson);
    return JSON.stringify(result);
  } catch (e) {
    return JSON.stringify({ "__error": true, "message": e.message || String(e) });
  }
})();
''';

    final result = await _evaluateJs(script);
    if (result == null || result == 'null') {
      throw Exception('Extractor returned null');
    }

    final decoded = jsonDecode(result) as Map<String, dynamic>;
    if (decoded['__error'] == true) {
      throw Exception(decoded['message'] as String? ?? 'JS execution error');
    }
    return decoded;
  }

  Future<String?> _evaluateJs(String script) async {
    final controller = await _getOrCreateController();
    final result = await controller.evaluateJavascript(source: script);
    if (result is String) return result;
    return result?.toString();
  }

  Future<InAppWebViewController> _getOrCreateController() async {
    if (_webViewController != null) return _webViewController!;

    final completer = Completer<InAppWebViewController>();

    _headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: false,
        databaseEnabled: false,
        cacheEnabled: false,
        useOnLoadResource: false,
        useShouldOverrideUrlLoading: false,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        completer.complete(controller);
      },
    );

    await _headless!.run();
    return completer.future;
  }

  void dispose() {
    _headless?.dispose();
    _headless = null;
    _webViewController = null;
    _jsCache.clear();
    _runtimeJs = null;
    _runtimeLoaded = false;
  }
}
