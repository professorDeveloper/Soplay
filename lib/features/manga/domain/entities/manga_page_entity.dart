class MangaPageEntity {
  final int index;

  final String imageUrl;

  /// `Cookie:` header value for this page's image host, when the source had
  /// cookies for it.
  ///
  /// Per-page rather than shared with the chapter's headers because image CDNs
  /// often sit on a different host than the API, and one host's cookies must
  /// not be sent to another. Null means "no cookies for this host" — which is
  /// the normal case for sources that are not behind Cloudflare.
  final String? cookie;

  const MangaPageEntity({
    required this.index,
    required this.imageUrl,
    this.cookie,
  });
}
