import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/tracker/data/tracker_link_store.dart';

export 'package:soplay/features/tracker/data/tracker_link_store.dart'
    show TrackerLink;

/// One local title tied to one MyAnimeList anime id.
typedef MalLink = TrackerLink;

/// The MyAnimeList half of the title map.
///
/// Deliberately its own storage rather than a second id on the AniList row:
/// disconnecting AniList clears the AniList map, and a shared row would take
/// every MAL association with it — including for someone who never connected
/// AniList in the first place.
///
/// Rows here are written automatically rather than chosen by hand. AniList is
/// the only side that can match a source title to anything, and it carries the
/// MAL id for the same entry (`idMal`), so a title the user links once serves
/// both trackers. See MalTracker for the fallback when it does not.
class MalLinkStore extends TrackerLinkStore {
  MalLinkStore({super.box});

  @override
  String get linksKey => AppConstants.malLinksKey;

  @override
  String get tombstonesKey => AppConstants.malLinkTombstonesKey;

  static String keyFor(String provider, String contentUrl) =>
      TrackerLinkStore.keyFor(provider, contentUrl);
}
