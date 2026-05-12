# Extractor Runner Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate backend's new provider mode system (server/hybrid/client) with client-side JS extraction via `flutter_inappwebview` HeadlessInAppWebView.

**Architecture:** Provider entity gets `mode` and `extractor` fields. New `ExtractorRunner` service uses HeadlessInAppWebView to execute server-provided JS extractors. New `ProviderManager` routes API calls based on provider mode — server calls go through existing Dio, hybrid/client calls use ExtractorRunner for media resolution (and full catalog for client mode). Existing clean architecture layers (entity → model → datasource → repository → usecase → bloc) are preserved.

**Tech Stack:** Flutter, flutter_inappwebview (HeadlessInAppWebView), Dio, GetIt DI, BLoC, Hive

---

## File Structure

### New files:
- `lib/core/extractor/extractor_entity.dart` — ExtractorEntity domain class
- `lib/core/extractor/extractor_model.dart` — ExtractorModel with fromJson
- `lib/core/extractor/extractor_runner.dart` — HeadlessInAppWebView JS runner service
- `lib/core/extractor/provider_manager.dart` — Mode-based routing (server/hybrid/client)

### Modified files:
- `lib/features/profile/domain/entities/provider_entity.dart` — Add `mode`, `extractor` fields
- `lib/features/profile/data/models/provider_model.dart` — Parse `mode`, `extractor` from JSON
- `lib/core/di/injection.dart` — Register ExtractorRunner, ProviderManager
- `pubspec.yaml` — Add `flutter_inappwebview` dependency

---

### Task 1: Add `flutter_inappwebview` dependency

**Files:**
- Modify: `pubspec.yaml:68`

- [ ] **Step 1: Add dependency to pubspec.yaml**

In `pubspec.yaml`, add `flutter_inappwebview` under dependencies after `video_player`:

```yaml
  flutter_inappwebview: ^6.2.1
```

- [ ] **Step 2: Run flutter pub get**

Run: `flutter pub get`
Expected: Dependencies resolved successfully.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat: add flutter_inappwebview dependency for JS extractor support"
```

---

### Task 2: Create ExtractorEntity and ExtractorModel

**Files:**
- Create: `lib/core/extractor/extractor_entity.dart`
- Create: `lib/core/extractor/extractor_model.dart`

- [ ] **Step 1: Create ExtractorEntity**

Create `lib/core/extractor/extractor_entity.dart`:

```dart
class ExtractorEntity {
  final String name;
  final int version;
  final String scope; // "all" | "resolveMedia"
  final String url;

  const ExtractorEntity({
    required this.name,
    required this.version,
    required this.scope,
    required this.url,
  });
}
```

- [ ] **Step 2: Create ExtractorModel**

Create `lib/core/extractor/extractor_model.dart`:

```dart
import 'extractor_entity.dart';

class ExtractorModel extends ExtractorEntity {
  const ExtractorModel({
    required super.name,
    required super.version,
    required super.scope,
    required super.url,
  });

  factory ExtractorModel.fromJson(Map<String, dynamic> json) {
    return ExtractorModel(
      name: json['name'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      scope: json['scope'] as String? ?? 'resolveMedia',
      url: json['url'] as String? ?? '',
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/core/extractor/
git commit -m "feat: add ExtractorEntity and ExtractorModel"
```

---

### Task 3: Update ProviderEntity and ProviderModel with mode/extractor

**Files:**
- Modify: `lib/features/profile/domain/entities/provider_entity.dart`
- Modify: `lib/features/profile/data/models/provider_model.dart`

- [ ] **Step 1: Update ProviderEntity**

Edit `lib/features/profile/domain/entities/provider_entity.dart` — add `mode` and `extractor` fields:

```dart
import 'package:soplay/core/extractor/extractor_entity.dart';

class ProviderEntity {
  final String id;
  final String name;
  final String image;
  final String url;
  final String description;
  final List<String> domains;
  final String mode; // "server" | "hybrid" | "client"
  final ExtractorEntity? extractor;

  const ProviderEntity({
    required this.id,
    required this.name,
    required this.image,
    required this.url,
    required this.description,
    required this.domains,
    this.mode = 'server',
    this.extractor,
  });
}
```

- [ ] **Step 2: Update ProviderModel**

Edit `lib/features/profile/data/models/provider_model.dart` — parse `mode` and `extractor`:

```dart
import 'package:soplay/core/extractor/extractor_model.dart';
import '../../domain/entities/provider_entity.dart';

class ProviderModel extends ProviderEntity {
  const ProviderModel({
    required super.id,
    required super.name,
    required super.image,
    required super.url,
    required super.description,
    required super.domains,
    super.mode,
    super.extractor,
  });

  factory ProviderModel.fromJson(Map<String, dynamic> json) {
    final id =
        json['id'] as String? ??
        json['_id'] as String? ??
        json['slug'] as String? ??
        '';
    final name = json['name'] as String? ?? id;

    final extractorJson = json['extractor'] as Map<String, dynamic>?;

    return ProviderModel(
      id: id,
      name: name,
      image: json['image'] as String? ?? '',
      url: json['url'] as String? ?? '',
      description: json['description'] as String? ?? '',
      domains: (json['domains'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      mode: json['mode'] as String? ?? 'server',
      extractor: extractorJson != null
          ? ExtractorModel.fromJson(extractorJson)
          : null,
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/profile/domain/entities/provider_entity.dart lib/features/profile/data/models/provider_model.dart
git commit -m "feat: add mode and extractor fields to ProviderEntity/Model"
```

---

### Task 4: Create ExtractorRunner service

**Files:**
- Create: `lib/core/extractor/extractor_runner.dart`

- [ ] **Step 1: Create ExtractorRunner**

Create `lib/core/extractor/extractor_runner.dart`:

```dart
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

  ExtractorRunner({required Dio dio}) : _dio = dio;

  /// Load and cache JS code from server
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
    }
  }

  /// Execute a JS method on the extractor and return parsed result
  Future<Map<String, dynamic>> call(
    String extractorName,
    String method, [
    dynamic args,
  ]) async {
    final js = _jsCache[extractorName];
    if (js == null) {
      throw Exception('Extractor "$extractorName" not loaded');
    }

    final argsJson = args != null ? jsonEncode(args) : '{}';

    final script = '''
(async () => {
  try {
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
        clearCache: true,
        useOnLoadResource: false,
        useShouldOverrideUrlLoading: false,
        mediaPlaybackRequiresUserGesture: false,
        disableDefaultErrorPage: true,
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
  }
}
```

Note: Add `import 'dart:async';` at the top for the Completer.

- [ ] **Step 2: Commit**

```bash
git add lib/core/extractor/extractor_runner.dart
git commit -m "feat: add ExtractorRunner service with HeadlessInAppWebView"
```

---

### Task 5: Create ProviderManager

**Files:**
- Create: `lib/core/extractor/provider_manager.dart`

- [ ] **Step 1: Create ProviderManager**

Create `lib/core/extractor/provider_manager.dart`:

```dart
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/extractor_runner.dart';
import 'package:soplay/features/detail/data/datasources/detail_data_source.dart';
import 'package:soplay/features/detail/data/models/media_resolve_model.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';

class ProviderManager {
  final DetailDataSource _detailDataSource;
  final HomeDataSource _homeDataSource;
  final ExtractorRunner _extractor;
  final List<ProviderEntity> _providers = [];

  ProviderManager({
    required DetailDataSource detailDataSource,
    required HomeDataSource homeDataSource,
    required ExtractorRunner extractor,
  })  : _detailDataSource = detailDataSource,
        _homeDataSource = homeDataSource,
        _extractor = extractor;

  void updateProviders(List<ProviderEntity> providers) {
    _providers
      ..clear()
      ..addAll(providers);
  }

  ProviderEntity? getProvider(String id) {
    try {
      return _providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  bool isServerMode(String providerId) {
    final provider = getProvider(providerId);
    return provider == null || provider.mode == 'server';
  }

  /// Resolve media — routes to server API or JS extractor based on mode
  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    final providerInfo = getProvider(provider);

    // Server mode or unknown provider — use existing API
    if (providerInfo == null || providerInfo.mode == 'server') {
      return _resolveViaServer(ref: ref, provider: provider, lang: lang);
    }

    // Hybrid or client mode — use JS extractor
    if (providerInfo.extractor == null) {
      return _resolveViaServer(ref: ref, provider: provider, lang: lang);
    }

    return _resolveViaExtractor(
      providerInfo: providerInfo,
      ref: ref,
      lang: lang,
    );
  }

  Future<Result<MediaResolveEntity>> _resolveViaServer({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    try {
      final result = await _detailDataSource.resolveMedia(
        ref: ref,
        provider: provider,
        lang: lang,
      );
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<MediaResolveEntity>> _resolveViaExtractor({
    required ProviderEntity providerInfo,
    required String ref,
    String? lang,
  }) async {
    try {
      final extractor = providerInfo.extractor!;
      await _extractor.loadExtractor(extractor);

      final args = <String, dynamic>{'ref': ref};
      if (lang != null && lang.isNotEmpty) args['lang'] = lang;

      final json = await _extractor.call(extractor.name, 'resolveMedia', args);
      final result = MediaResolveModel.fromJson(json);
      return Success(result);
    } catch (e) {
      return Failure(
        Exception('Extractor xatolik: ${e.toString()}'),
      );
    }
  }

  /// Get home data — routes to server API or JS extractor based on mode
  Future<Result<HomeDataEntity>> getHome(String providerId) async {
    final providerInfo = getProvider(providerId);

    // Client mode — use JS extractor for everything
    if (providerInfo != null &&
        providerInfo.mode == 'client' &&
        providerInfo.extractor != null &&
        providerInfo.extractor!.scope == 'all') {
      return _getHomeViaExtractor(providerInfo);
    }

    // Server or hybrid — use existing API
    return _getHomeViaServer();
  }

  Future<Result<HomeDataEntity>> _getHomeViaServer() async {
    try {
      final result = await _homeDataSource.loadHome();
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  Future<Result<HomeDataEntity>> _getHomeViaExtractor(
    ProviderEntity providerInfo,
  ) async {
    try {
      final extractor = providerInfo.extractor!;
      await _extractor.loadExtractor(extractor);

      final json = await _extractor.call(extractor.name, 'getHome', {});
      final result = HomeDataModel.fromJson(json);
      return Success(result);
    } catch (e) {
      return Failure(
        Exception('Extractor xatolik: ${e.toString()}'),
      );
    }
  }

  void dispose() {
    _extractor.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/extractor/provider_manager.dart
git commit -m "feat: add ProviderManager for mode-based routing"
```

---

### Task 6: Register new services in DI

**Files:**
- Modify: `lib/core/di/injection.dart`

- [ ] **Step 1: Add imports and register ExtractorRunner + ProviderManager**

Add imports at the top of `injection.dart`:

```dart
import 'package:soplay/core/extractor/extractor_runner.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
```

After registering `Dio` singleton (line 90) and before registering datasources, add:

```dart
getIt.registerSingleton<ExtractorRunner>(
  ExtractorRunner(dio: getIt<Dio>()),
);
```

After registering `DetailDataSource` (line 98) and `HomeDataSource` (line 95), add:

```dart
getIt.registerSingleton<ProviderManager>(
  ProviderManager(
    detailDataSource: getIt<DetailDataSource>(),
    homeDataSource: getIt<HomeDataSource>(),
    extractor: getIt<ExtractorRunner>(),
  ),
);
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/di/injection.dart
git commit -m "feat: register ExtractorRunner and ProviderManager in DI"
```

---

### Task 7: Wire ProviderManager into ProviderBloc

**Files:**
- Modify: `lib/features/profile/presentation/bloc/provider_bloc.dart`

- [ ] **Step 1: Update ProviderBloc to sync providers to ProviderManager**

After providers are loaded in `_onLoad`, call `providerManager.updateProviders()`:

```dart
import 'package:soplay/core/extractor/provider_manager.dart';
```

Add `ProviderManager` dependency to constructor:

```dart
class ProviderBloc extends Bloc<ProviderEvent, ProviderState> {
  final GetProvidersUseCase useCase;
  final HiveService hiveService;
  final ProviderManager providerManager;

  ProviderBloc({
    required this.useCase,
    required this.hiveService,
    required this.providerManager,
  }) : super(ProviderInitial()) {
    on<ProviderLoad>(_onLoad);
    on<ProviderSelect>(_onSelect);
  }
```

In `_onLoad`, after `emit(ProviderLoaded(...))`, add before it:

```dart
providerManager.updateProviders(providers);
```

- [ ] **Step 2: Update DI registration for ProviderBloc**

In `injection.dart`, update ProviderBloc factory:

```dart
getIt.registerFactory(
  () => ProviderBloc(
    useCase: getIt<GetProvidersUseCase>(),
    hiveService: getIt<HiveService>(),
    providerManager: getIt<ProviderManager>(),
  ),
);
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/profile/presentation/bloc/provider_bloc.dart lib/core/di/injection.dart
git commit -m "feat: sync provider list to ProviderManager via ProviderBloc"
```

---

### Task 8: Wire ProviderManager into player's media resolution

**Files:**
- Modify: `lib/features/detail/presentation/pages/player_page.dart`

- [ ] **Step 1: Replace direct ResolveMediaUseCase with ProviderManager**

In `player_page.dart`, change the `_resolve` field (line 58):

From:
```dart
final ResolveMediaUseCase _resolve = getIt<ResolveMediaUseCase>();
```

To:
```dart
final ResolveMediaUseCase _resolve = getIt<ResolveMediaUseCase>();
final ProviderManager _providerManager = getIt<ProviderManager>();
```

Add import:
```dart
import 'package:soplay/core/extractor/provider_manager.dart';
```

- [ ] **Step 2: Update _loadEpisode to use ProviderManager for non-server providers**

In the `_loadEpisode` method (around line 399), change the resolve call:

From:
```dart
final result = await _resolve(
  ref: ep.mediaRef,
  provider: widget.args.provider,
  lang: lang,
);
```

To:
```dart
final provider = widget.args.provider;
final Result<MediaResolveEntity> result;
if (_providerManager.isServerMode(provider)) {
  result = await _resolve(
    ref: ep.mediaRef,
    provider: provider,
    lang: lang,
  );
} else {
  result = await _providerManager.resolveMedia(
    ref: ep.mediaRef,
    provider: provider,
    lang: lang,
  );
}
```

Add import:
```dart
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
```

Note: `MediaResolveEntity` import may already exist indirectly via `video_source_entity.dart`, but ensure it's explicitly imported.

- [ ] **Step 3: Commit**

```bash
git add lib/features/detail/presentation/pages/player_page.dart
git commit -m "feat: route media resolution through ProviderManager for hybrid/client providers"
```

---

### Task 9: Remove hardcoded _defaultRefererFor (headers now come from API)

**Files:**
- Modify: `lib/features/detail/presentation/pages/player_page.dart`

- [ ] **Step 1: Clean up _defaultRefererFor**

Since headers now come from the API response, the hardcoded `_defaultRefererFor` method is no longer needed for new providers. However, keep it for backward compatibility with providers that might not send headers yet. No change needed — the current logic already merges API headers on top of defaults (`mergedHeaders.addAll(headers)` at line 624), so API headers will override defaults correctly.

This step is a no-op. The existing code handles this correctly already.

- [ ] **Step 2: Commit (skip if no changes)**

No commit needed.

---

### Task 10: Verify and test

- [ ] **Step 1: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 2: Build test**

Run: `flutter build apk --debug`
Expected: Build succeeds.

- [ ] **Step 3: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: resolve analyzer issues from extractor integration"
```
