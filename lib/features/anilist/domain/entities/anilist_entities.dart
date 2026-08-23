/// The AniList account a stored token belongs to.
class AnilistViewer {
  const AnilistViewer({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.siteUrl,
  });

  final int id;
  final String name;
  final String? avatarUrl;
  final String? siteUrl;

  factory AnilistViewer.fromJson(Map<String, dynamic> json) => AnilistViewer(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    avatarUrl: (json['avatar'] as Map?)?['large'] as String?,
    siteUrl: json['siteUrl'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'siteUrl': siteUrl,
  };
}

/// The next episode AniList expects to air.
///
/// [airingAt] is a UNIX second, not a millisecond — the whole AniList API deals
/// in seconds, and multiplying at the boundary keeps that conversion in exactly
/// one place.
class AnilistAiring {
  const AnilistAiring({required this.episode, required this.airingAt});

  final int episode;
  final int airingAt;

  DateTime get airsAt =>
      DateTime.fromMillisecondsSinceEpoch(airingAt * 1000, isUtc: true).toLocal();

  /// Time left, recomputed from the clock on every read.
  ///
  /// AniList also returns `timeUntilAiring`, but that value is frozen at the
  /// moment of the response — a screen left open would count down from a stale
  /// number, or show a negative one.
  Duration get timeLeft => airsAt.difference(DateTime.now());

  bool get hasAired => timeLeft.isNegative;

  static AnilistAiring? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final airingAt = (json['airingAt'] as num?)?.toInt();
    if (airingAt == null || airingAt <= 0) return null;
    return AnilistAiring(
      episode: (json['episode'] as num?)?.toInt() ?? 0,
      airingAt: airingAt,
    );
  }
}

/// One anime on AniList.
/// One episode of one show, at the minute it goes out.
///
/// Distinct from [AnilistAiring], which hangs off a media object and only ever
/// describes that show's NEXT episode. The calendar asks the opposite question
/// — what airs in this window — so the airing is the subject and the media is
/// the detail.
class AnilistScheduledAiring {
  const AnilistScheduledAiring({
    required this.media,
    required this.episode,
    required this.airingAt,
  });

  final AnilistMedia media;
  final int episode;
  final int airingAt;

  DateTime get airsAt =>
      DateTime.fromMillisecondsSinceEpoch(airingAt * 1000, isUtc: true).toLocal();

  bool get hasAired => airsAt.isBefore(DateTime.now());

  static AnilistScheduledAiring? fromJson(Map<String, dynamic> json) {
    final rawMedia = json['media'];
    final airingAt = (json['airingAt'] as num?)?.toInt();
    if (rawMedia is! Map || airingAt == null) return null;
    return AnilistScheduledAiring(
      media: AnilistMedia.fromJson(rawMedia.cast<String, dynamic>()),
      episode: (json['episode'] as num?)?.toInt() ?? 0,
      airingAt: airingAt,
    );
  }
}

class AnilistMedia {
  const AnilistMedia({
    required this.id,
    this.idMal,
    this.romajiTitle,
    this.englishTitle,
    this.nativeTitle,
    this.coverImage,
    this.bannerImage,
    this.description,
    this.episodes,
    this.averageScore,
    this.seasonYear,
    this.format,
    this.status,
    this.siteUrl,
    this.nextAiring,
    this.isAdult = false,
  });

  final int id;

  /// The same show's id on MyAnimeList, when AniList knows one.
  ///
  /// Carried so that linking a title ONCE serves both trackers: AniList is the
  /// only side that can match a source title to anything, and it happens to
  /// hold MAL's id for the same entry. Without this the MAL tracker would need
  /// its own search and its own link sheet to learn what the user already told
  /// us. Null for entries AniList has no MAL counterpart for.
  final int? idMal;

  final String? romajiTitle;
  final String? englishTitle;
  final String? nativeTitle;
  final String? coverImage;
  final String? bannerImage;
  final String? description;
  final int? episodes;
  final int? averageScore;
  final int? seasonYear;
  final String? format;
  final String? status;
  final String? siteUrl;
  final AnilistAiring? nextAiring;
  final bool isAdult;

  /// Episodes that exist to watch right now.
  ///
  /// For an airing show AniList keeps `episodes` at the announced season total
  /// while only `nextAiring.episode - 1` have actually gone out. Offering to
  /// mark an unaired episode watched is nonsense, so callers cap against this.
  int? get airedEpisodes {
    final next = nextAiring;
    if (next != null && next.episode > 0) return next.episode - 1;
    return episodes;
  }

  /// What to show, and what to search sources with.
  ///
  /// English first: source sites are indexed under the title people actually
  /// type, and a romaji-only search misses far more than it finds.
  String get displayTitle =>
      (englishTitle?.trim().isNotEmpty ?? false)
      ? englishTitle!
      : (romajiTitle?.trim().isNotEmpty ?? false)
      ? romajiTitle!
      : (nativeTitle ?? '');

  /// Every title worth trying against a source, best guess first and no blanks
  /// or duplicates. A source that does not carry the English title often
  /// carries the romaji one.
  List<String> get searchTitles {
    final seen = <String>{};
    return [
      for (final t in [englishTitle, romajiTitle, nativeTitle])
        if (t != null && t.trim().isNotEmpty && seen.add(t.trim())) t.trim(),
    ];
  }

  factory AnilistMedia.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as Map?)?.cast<String, dynamic>();
    return AnilistMedia(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idMal: (json['idMal'] as num?)?.toInt(),
      romajiTitle: title?['romaji'] as String?,
      englishTitle: title?['english'] as String?,
      nativeTitle: title?['native'] as String?,
      coverImage: (json['coverImage'] as Map?)?['large'] as String?,
      bannerImage: json['bannerImage'] as String?,
      description: json['description'] as String?,
      episodes: (json['episodes'] as num?)?.toInt(),
      averageScore: (json['averageScore'] as num?)?.toInt(),
      seasonYear: (json['seasonYear'] as num?)?.toInt(),
      format: json['format'] as String?,
      status: json['status'] as String?,
      siteUrl: json['siteUrl'] as String?,
      nextAiring: AnilistAiring.fromJson(
        (json['nextAiringEpisode'] as Map?)?.cast<String, dynamic>(),
      ),
      isAdult: json['isAdult'] == true,
    );
  }
}

/// One row of the viewer's AniList library.
class AnilistListEntry {
  const AnilistListEntry({
    required this.id,
    required this.media,
    required this.status,
    required this.progress,
    this.score,
    this.updatedAt,
  });

  final int id;
  final AnilistMedia media;

  /// AniList's own status: CURRENT, PLANNING, COMPLETED, DROPPED, PAUSED, REPEATING.
  final String status;

  /// Episodes FINISHED, not an index.
  final int progress;
  final double? score;
  final int? updatedAt;

  /// How far through, when the total is known. Null for an ongoing show with no
  /// announced episode count, where a bar would be a guess.
  double? get completion {
    final total = media.episodes;
    if (total == null || total <= 0) return null;
    return (progress / total).clamp(0.0, 1.0);
  }

  /// The next episode to watch, or null when there is nothing left aired.
  ///
  /// Capped against what has actually aired rather than the announced total,
  /// so a weekly show stops offering "+1" once the viewer has caught up.
  int? get nextEpisode {
    final aired = media.airedEpisodes;
    if (aired != null && progress >= aired) return null;
    return progress + 1;
  }

  /// Episodes aired but not yet watched. 0 when caught up or unknown.
  int get behindBy {
    final aired = media.airedEpisodes;
    if (aired == null) return 0;
    final behind = aired - progress;
    return behind > 0 ? behind : 0;
  }

  AnilistListEntry copyWith({int? progress, String? status}) =>
      AnilistListEntry(
        id: id,
        media: media,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        score: score,
        updatedAt: updatedAt,
      );

  factory AnilistListEntry.fromJson(Map<String, dynamic> json) =>
      AnilistListEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        media: AnilistMedia.fromJson(
          (json['media'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        status: json['status'] as String? ?? 'CURRENT',
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble(),
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
      );
}

/// The statuses AniList exposes, in the order a library reads best.
///
/// [labelKey] rather than a literal: this list is rendered in three languages,
/// and an English constant baked into the enum would leak into all of them.
enum AnilistStatus {
  current('CURRENT', 'anilist.status_current'),
  repeating('REPEATING', 'anilist.status_repeating'),
  planning('PLANNING', 'anilist.status_planning'),
  completed('COMPLETED', 'anilist.status_completed'),
  paused('PAUSED', 'anilist.status_paused'),
  dropped('DROPPED', 'anilist.status_dropped');

  const AnilistStatus(this.value, this.labelKey);
  final String value;
  final String labelKey;

  static AnilistStatus? fromValue(String? value) {
    for (final s in AnilistStatus.values) {
      if (s.value == value) return s;
    }
    return null;
  }
}
