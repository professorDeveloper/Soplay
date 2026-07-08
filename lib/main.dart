import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/deeplink/deeplink_service.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/system/app_orientation.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

import 'app.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopPlatform) {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
  }
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  await Future.wait([
    EasyLocalization.ensureInitialized(),
    _initHive(),
  ]);
  if (isDesktopPlatform) {
    final native = Hive.box(AppConstants.settingsBox)
        .get('use_native_title_bar', defaultValue: false) == true;
    try {
      await windowManager.setTitleBarStyle(
        native ? TitleBarStyle.normal : TitleBarStyle.hidden,
        // macOS: keep the native traffic-light buttons visible in BOTH modes —
        // in custom (hidden) mode they're the only window controls (our strip
        // draws no buttons on macOS). On Windows/Linux the custom strip draws
        // its own buttons, so hide the native ones when custom.
        windowButtonVisibility: Platform.isMacOS ? true : native,
      );
      await windowManager.setMinimumSize(const Size(800, 560));
    } catch (_) {}
    DesktopWindow.nativeTitleBar.value = native;
  }

  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  await _initFirebaseSafely();
  await configureDependencies();
  if (!Platform.isAndroid) {
    ExtensionBridge.setUrl(getIt<HiveService>().getBridgeUrl());
  }
  _fireAndForget(getIt<DownloadService>().resumeIncomplete(), 'download');
  _fireAndForget(getIt<ProviderRegistry>().preload(), 'providers');
  _fireAndForget(getIt<JsRuntimeService>().ensureReady(), 'js');
  _fireAndForget(
    getIt<NotificationService>().ensureInitialized(),
    'fcm',
  );
  _fireAndForget(getIt<DeeplinkService>().start(), 'deeplink');
  unawaited(
    AppOrientation.set([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).catchError((Object _) {}),
  );
  unawaited(
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    ).catchError((Object _) {}),
  );
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('uz'),
        Locale('ru'),
      ],

      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const MyApp(),
    ),
  );
}

Future<void> _initHive() async {
  if (isDesktopPlatform) {
    final dir = await getApplicationSupportDirectory();
    Hive.init(dir.path);
  } else {
    await Hive.initFlutter();
  }
  await Future.wait([
    Hive.openBox(AppConstants.authBox),
    Hive.openBox(AppConstants.settingsBox),
    Hive.openBox(AppConstants.historyBox),
    Hive.openBox(AppConstants.downloadBox),
    Hive.openBox(AppConstants.extractorsBox),
    Hive.openBox(AppConstants.streakBox),
    Hive.openBox(AppConstants.favoritesBox),
    Hive.openBox(AppConstants.privateFavoritesBox),
  ]);
}

void _fireAndForget(Future<void> future, String tag) {
  future.catchError((Object e) {
    if (kDebugMode) debugPrint('[$tag] background init failed: $e');
  });
}

Future<void> _initFirebaseSafely() async {
  if (!Platform.isAndroid) return;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    if (kDebugMode) debugPrint('[Firebase] init failed: $e');
  }
}
