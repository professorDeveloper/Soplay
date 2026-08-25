import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Resolved once at startup by [initTvPlatform]. Never mutated afterwards.
///
/// Defaults to `false` so every read before (or without) resolution takes the
/// phone/desktop path the app ships today.
bool _isTv = false;
bool _tvResolved = false;

const MethodChannel _platformChannel = MethodChannel('soplay/platform');

/// True only on Android TV / Google TV / Fire TV (leanback devices).
///
/// Cheap and synchronous — a plain field read, safe to call from `build()` and
/// from `main()` before any widget exists. Provably false on iOS, Windows,
/// Linux, macOS and every Android phone: the only writer is [initTvPlatform],
/// which is a no-op off Android and asks the platform for FEATURE_LEANBACK /
/// UI_MODE_TYPE_TELEVISION everywhere else.
bool get isTvPlatform => _isTv;

/// Resolve [isTvPlatform] once, as early as possible in `main()` — it must be
/// awaited *before* the first [isMobilePlatform] branch runs, otherwise the
/// liquid-glass phone path fires on a television.
///
/// Idempotent, never throws, and safe to call off Android (returns immediately).
/// Any failure leaves the flag `false`, i.e. today's phone behaviour.
Future<void> initTvPlatform() async {
  if (_tvResolved) return;
  _tvResolved = true;
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    _isTv = await _platformChannel.invokeMethod<bool>('isTv') ?? false;
  } catch (_) {
    _isTv = false;
  }
}

/// Test-only override. Production code must go through [initTvPlatform].
@visibleForTesting
void debugSetTvPlatform(bool value) {
  _isTv = value;
  _tvResolved = true;
}

/// Resolved once at startup by [initNativeGlass]. Never mutated afterwards.
///
/// False until resolved, so any read before it lands takes the Flutter-shader
/// path the app already shipped.
bool _nativeGlass = false;
bool _nativeGlassResolved = false;

const MethodChannel _liquidGlassChannel = MethodChannel('soplay/liquid_glass');

/// True only where the OS can provide real Liquid Glass — iOS 26+, in a binary
/// actually built against the iOS 26 SDK.
///
/// Both halves of that matter. Checking the OS version from Dart would answer
/// yes on an iOS 26 device running a build made with an older Xcode, where
/// `UIGlassEffect` simply does not exist in the binary — and the app would ship
/// a navigation bar that renders as a transparent hole. Only the native side
/// can see whether the class is there, so only the native side is asked.
bool get supportsNativeLiquidGlass => _nativeGlass;

/// Resolve [supportsNativeLiquidGlass] once, alongside [initTvPlatform].
///
/// Idempotent, never throws, and returns immediately off iOS. Any failure
/// leaves the flag false, i.e. today's behaviour.
Future<void> initNativeGlass() async {
  if (_nativeGlassResolved) return;
  _nativeGlassResolved = true;
  if (kIsWeb || !Platform.isIOS) return;
  try {
    _nativeGlass =
        await _liquidGlassChannel.invokeMethod<bool>('isAvailable') ?? false;
  } catch (_) {
    _nativeGlass = false;
  }
}

/// Where the app has to *emulate* glass with Flutter shaders.
///
/// This is the axis the shader runtime should have been gated on all along.
/// `isMobilePlatform` answers "is this a phone", which is the right question
/// for layout and the wrong one for "do we need a GLSL glass pipeline" — on
/// iOS 26 the system provides the material, so compiling shaders and wrapping
/// the whole app in an adaptive-quality scope is pure cost for a worse result.
bool get usesFlutterGlass => isMobilePlatform && !supportsNativeLiquidGlass;

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

// Android TV reports Platform.isAndroid, but it is not a phone: the liquid-glass
// bottom nav and its shader pre-warm are phone affordances that are wrong on a
// television. Phone and iOS evaluation is unchanged — _isTv is false there, so
// `Platform.isAndroid && !false` is exactly `Platform.isAndroid`.
bool get isMobilePlatform =>
    !kIsWeb && ((Platform.isAndroid && !_isTv) || Platform.isIOS);
