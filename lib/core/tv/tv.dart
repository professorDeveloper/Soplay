/// The Android TV focus layer.
///
/// Everything exported here is inert when `isTvPlatform` is false: the widgets
/// return their child untouched, the helpers return early, and no focus nodes
/// or animations are created. Import this barrel rather than the parts.
library;

export 'package:soplay/core/system/platform_utils.dart' show isTvPlatform;

export 'tv_focusable.dart';
export 'tv_keys.dart';
