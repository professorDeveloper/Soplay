class ExtractorEntity {
  final String name;
  final int version;
  final String scope; // "all" | "resolveMedia"
  final String url;

  const ExtractorEntity({
    required this.name,
    required this.version,
    required this.scope,
    required this.url,
  });
}
