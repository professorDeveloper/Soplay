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

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

// Android TV reports Platform.isAndroid, but it is not a phone: the liquid-glass
// bottom nav and its shader pre-warm are phone affordances that are wrong on a
// television. Phone and iOS evaluation is unchanged — _isTv is false there, so
// `Platform.isAndroid && !false` is exactly `Platform.isAndroid`.
bool get isMobilePlatform =>
    !kIsWeb && ((Platform.isAndroid && !_isTv) || Platform.isIOS);
