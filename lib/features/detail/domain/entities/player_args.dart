import 'episode_entity.dart';
import 'extractor_config_entity.dart';
import 'thumbnails_entity.dart';
import 'video_source_entity.dart';

class PlayerArgs {
  final String title;
  final String provider;
  final String? contentUrl;
  final String? thumbnail;
  final String? movieUrl;
  final String? type;
  final List<VideoSourceEntity> videoSources;
  final Map<String, String> headers;
  final List<EpisodeEntity> episodes;
  final int initialEpisodeIndex;
  final String? initialLang;
  final Duration resumePosition;
  final bool showDownloadAction;
  final ThumbnailsEntity? thumbnails;

  // Watch2Gether identity: lets a movie carry its resolvable ref/lang and lets
  // the player know which party (if any) it belongs to. `provider` and
  // `contentUrl` already exist above.
  /// The sniff directive the server sent with this media, if any.
  ///
  /// The serial path re-resolves inside the player and picks this up on its
  /// own. The movie path resolves on the detail page and used to hand the
  /// player only the url, so a source whose url is an embed page — the whole
  /// point of the directive — reached ExoPlayer as HTML and failed with
  /// UnrecognizedInputFormatException. Carrying it here is what lets a hybrid
  /// movie play at all.
  final ExtractorConfigEntity? extractor;

  final String? mediaRef;
  final String? lang;
  final String? partyCode;

  const PlayerArgs({
    required this.title,
    required this.provider,
    required this.headers,
    this.contentUrl,
    this.thumbnail,
    this.movieUrl,
    this.type,
    this.videoSources = const [],
    this.episodes = const [],
    this.initialEpisodeIndex = 0,
    this.initialLang,
    this.resumePosition = Duration.zero,
    this.showDownloadAction = true,
    this.thumbnails,
    this.extractor,
    this.mediaRef,
    this.lang,
    this.partyCode,
  });

  bool get isSerial => episodes.isNotEmpty;
}
