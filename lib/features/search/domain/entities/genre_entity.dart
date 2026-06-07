class GenreEntity {
  final String provider;
  final String slug;
  final String url;
  final String image;
  /// Optional human-readable label (CloudStream categories carry a real name
  /// while `slug` is a raw API path). Empty for backend genres → UI derives the
  /// label from `slug`.
  final String name;

  GenreEntity({
    required this.provider,
    required this.slug,
    required this.image,
    required this.url,
    this.name = '',
  });
}
