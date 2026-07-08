import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool get isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
