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
  // Desktop video playback (media_kit / libmpv). No-op / not called on mobile,
  // which keeps using the native video_player backend.
  if (isDesktopPlatform) {
    MediaKit.ensureInitialized();
    // Window control for the player's true-fullscreen toggle.
    await windowManager.ensureInitialized();
  }
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  await Future.wait([
    EasyLocalization.ensureInitialized(),
    _initHive(),
  ]);

  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  await _initFirebaseSafely();
  await configureDependencies();
  // Desktop / iOS: route extension calls to the phone's shared bridge, using the
  // link the user saved (phone + this device on the same Wi-Fi).
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
  // Baseline: system bars visible (non-fullscreen). The player enters immersive
  // mode itself and restores to this on exit — so a missed restore (e.g. a crash
  // in the player) can't leave the whole app stuck fullscreen.
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
    // On Windows, getApplicationDocumentsDirectory() can resolve to a
    // OneDrive-synced folder, which locks Hive's files mid-write (rename →
    // "access denied"). Store boxes in the (non-synced) app support dir.
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
