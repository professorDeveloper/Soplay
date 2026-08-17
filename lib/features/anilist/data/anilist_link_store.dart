import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// Remembers which AniList title a locally-watched title corresponds to.
///
/// This mapping is the whole reason tracking works for sources AniList has
/// never heard of. A CloudStream or Aniyomi extension gives us a title string
/// and a URL; AniList wants a numeric media id. Nothing in either can derive
/// the other, so the association is stored once — by the user, or by an exact
/// title match — and reused for every episode after that.
///
/// Keyed by provider AND url: the same show carried by two sources is two
/// separate links, because the episode numbering often differs between them.
class AnilistLinkStore {
  AnilistLinkStore({Box? box}) : _override = box;

  final Box? _override;
  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  Map<String, dynamic> _read() {
    final raw = _box.get(AppConstants.aniListLinksKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        // Corrupt value — treat as empty rather than crashing every lookup.
      }
    }
    return <String, dynamic>{};
  }

  Future<void> _write(Map<String, dynamic> map) =>
      _box.put(AppConstants.aniListLinksKey, jsonEncode(map));

  /// The identity of a local title. Trimmed and lowercased so a URL that
  /// differs only in case does not create a second, unlinked entry.
  static String keyFor(String provider, String contentUrl) =>
      '${provider.trim().toLowerCase()}|${contentUrl.trim().toLowerCase()}';

  AnilistLink? get(String provider, String contentUrl) {
    if (contentUrl.trim().isEmpty) return null;
    final raw = _read()[keyFor(provider, contentUrl)];
    if (raw is Map) return AnilistLink.fromJson(raw.cast<String, dynamic>());
    return null;
  }

  int? mediaIdFor(String provider, String contentUrl) =>
      get(provider, contentUrl)?.mediaId;

  Future<void> save(AnilistLink link) async {
    if (link.contentUrl.trim().isEmpty || link.mediaId <= 0) return;
    final map = _read()..[keyFor(link.provider, link.contentUrl)] = link.toJson();
    await _write(map);
  }

  Future<void> remove(String provider, String contentUrl) async {
    final map = _read()..remove(keyFor(provider, contentUrl));
    await _write(map);
  }

  /// Every link, newest first — for a "linked titles" screen and for deciding
  /// whether an auto-match has already been attempted.
  List<AnilistLink> all() {
    final out = [
      for (final raw in _read().values)
        if (raw is Map) AnilistLink.fromJson(raw.cast<String, dynamic>()),
    ];
    out.sort((a, b) => b.linkedAt.compareTo(a.linkedAt));
    return out;
  }

  /// Drops every link.
  ///
  /// Called on sign-out: these describe what one account watches and where, and
  /// leaving them behind would attribute the next person's viewing to a
  /// stranger's AniList list.
  Future<void> clear() => _box.delete(AppConstants.aniListLinksKey);
}

/// One local title tied to one AniList media id.
class AnilistLink {
  const AnilistLink({
    required this.provider,
    required this.contentUrl,
    required this.mediaId,
    required this.title,
    this.coverImage,
    this.totalEpisodes,
    this.linkedAt = 0,
    this.auto = false,
  });

  final String provider;
  final String contentUrl;
  final int mediaId;
  final String title;
  final String? coverImage;
  final int? totalEpisodes;
  final int linkedAt;

  /// True when the match was made by title rather than chosen by the user.
  /// Surfaced in the UI so a wrong automatic guess is visibly a guess.
  final bool auto;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'contentUrl': contentUrl,
        'mediaId': mediaId,
        'title': title,
        'coverImage': ?coverImage,
        'totalEpisodes': ?totalEpisodes,
        'linkedAt': linkedAt,
        'auto': auto,
      };

  factory AnilistLink.fromJson(Map<String, dynamic> j) => AnilistLink(
        provider: (j['provider'] ?? '').toString(),
        contentUrl: (j['contentUrl'] ?? '').toString(),
        mediaId: (j['mediaId'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        coverImage: j['coverImage'] as String?,
        totalEpisodes: (j['totalEpisodes'] as num?)?.toInt(),
        linkedAt: (j['linkedAt'] as num?)?.toInt() ?? 0,
        auto: j['auto'] as bool? ?? false,
      );
}
