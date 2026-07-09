/// Identity of what a party is watching. NEVER carries a resolved stream URL —
/// the server strips any such field. Each device resolves the stream itself
/// from this identity.
class PartyContent {
  final String? provider;
  final String? contentUrl;
  final String? mediaRef;
  final String? title;
  final String? thumbnail;
  final String? type;
  final String? server;
  final String? lang;
  final int? season;
  final int? episode;

  const PartyContent({
    this.provider,
    this.contentUrl,
    this.mediaRef,
    this.title,
    this.thumbnail,
    this.type,
    this.server,
    this.lang,
    this.season,
    this.episode,
  });

  factory PartyContent.fromJson(Map<String, dynamic> j) => PartyContent(
        provider: j['provider'] as String?,
        contentUrl: j['contentUrl'] as String?,
        mediaRef: j['mediaRef'] as String?,
        title: j['title'] as String?,
        thumbnail: j['thumbnail'] as String?,
        type: j['type'] as String?,
        server: j['server'] as String?,
        lang: j['lang'] as String?,
        season: (j['season'] as num?)?.toInt(),
        episode: (j['episode'] as num?)?.toInt(),
      );

  /// Identity-only JSON, nulls omitted. Deliberately has no url/stream field.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (provider != null) 'provider': provider,
        if (contentUrl != null) 'contentUrl': contentUrl,
        if (mediaRef != null) 'mediaRef': mediaRef,
        if (title != null) 'title': title,
        if (thumbnail != null) 'thumbnail': thumbnail,
        if (type != null) 'type': type,
        if (server != null) 'server': server,
        if (lang != null) 'lang': lang,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
      };

  bool get isEmpty =>
      provider == null &&
      contentUrl == null &&
      mediaRef == null &&
      title == null;

  bool get playable => mediaRef != null && provider != null;
}
