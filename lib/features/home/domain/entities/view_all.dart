class ViewAllEntity {
  final String type;
  final String slug;
  /// Human-readable section title for the app bar (the `slug` may be a raw API
  /// URL for CloudStream sections, so we carry the label separately).
  final String name;

  ViewAllEntity({required this.slug, required this.type, this.name = ''});
}
