import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/tracker/data/tracker_link_store.dart';

export 'package:soplay/features/tracker/data/tracker_link_store.dart'
    show TrackerLink;

/// One local title tied to one AniList media id.
///
/// The row shape is shared with every other tracker — see [TrackerLink]. The
/// alias is kept because the name reads correctly at the AniList call sites,
/// and because renaming thirteen files would have been churn, not clarity.
typedef AnilistLink = TrackerLink;

/// The AniList half of the title map.
///
/// Everything that decides anything lives in [TrackerLinkStore]; this names the
/// two Hive keys AniList owns.
class AnilistLinkStore extends TrackerLinkStore {
  AnilistLinkStore({super.box});

  @override
  String get linksKey => AppConstants.aniListLinksKey;

  @override
  String get tombstonesKey => AppConstants.aniListLinkTombstonesKey;

  /// Statics are not inherited in Dart, and the tracker calls this by name.
  static String keyFor(String provider, String contentUrl) =>
      TrackerLinkStore.keyFor(provider, contentUrl);
}
