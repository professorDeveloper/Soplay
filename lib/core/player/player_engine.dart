import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/system/platform_utils.dart';

/// Playback backend for the in-app player.
///
/// Only ever chosen by the user on Android. Desktop is pinned to [mediaKit]
/// (libmpv is the only backend that exists there) and iOS is pinned to
/// [native] — `media_kit_libs_ios_video` is deliberately not a dependency, so
/// there is no libmpv to fall back to on that platform.
enum PlayerEngine {
  /// `video_player` — ExoPlayer on Android. What the app has always shipped.
  /// No audio-track switching: the platform API simply does not expose it.
  native('default'),

  /// `media_kit` — libmpv. Exposes audio and subtitle track selection.
  mediaKit('media_kit'),

  /// Hand the stream off to VLC / MX Player via an ACTION_VIEW intent.
  /// Playback leaves the app entirely, so no in-app controls apply.
  external('external');

  const PlayerEngine(this.id);

  /// Stable string persisted in Hive. Never renumber or reorder — the stored
  /// value outlives the enum's index.
  final String id;

  static PlayerEngine fromId(String? id) {
    for (final e in PlayerEngine.values) {
      if (e.id == id) return e;
    }
    return PlayerEngine.native;
  }
}

/// The engine that should actually be used right now.
///
/// Reads Hive on every call rather than caching, so flipping the setting takes
/// effect on the very next playback with no app restart. The read is an
/// in-memory map lookup on an already-open box — cheap enough to call per load.
///
/// Falls back to [PlayerEngine.native] if the box is not open (unit tests, or
/// any call before `_initHive`), which is the pre-existing behaviour.
PlayerEngine resolvePlayerEngine() {
  // Desktop has no native backend at all; iOS has no libmpv. Neither platform
  // is user-selectable, so don't even look at the stored value there.
  if (isDesktopPlatform) return PlayerEngine.mediaKit;
  if (kIsWeb || !Platform.isAndroid) return PlayerEngine.native;
  try {
    final box = Hive.box(AppConstants.settingsBox);
    return PlayerEngine.fromId(
      box.get(
        AppConstants.playerEngineKey,
        defaultValue: AppConstants.defaultPlayerEngine,
      ) as String?,
    );
  } catch (_) {
    return PlayerEngine.native;
  }
}

/// Whether the engine picker should be offered at all. Android-only: every
/// other platform is pinned, so showing the control would be a lie.
bool get canChoosePlayerEngine =>
    !kIsWeb && Platform.isAndroid && !isDesktopPlatform;
