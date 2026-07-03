import 'dart:io';

import 'package:flutter/foundation.dart';

/// True on desktop platforms (Windows / Linux / macOS).
///
/// Desktop gets its own code paths (media_kit playback, side-rail navigation)
/// while mobile keeps the existing native implementations untouched.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// True on mobile platforms (Android / iOS).
bool get isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
