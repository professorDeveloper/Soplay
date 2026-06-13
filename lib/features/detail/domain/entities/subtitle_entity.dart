class SubtitleEntity {
  final String label;
  final String file;
  final bool isDefault;
  final Map<String, String> headers;

  const SubtitleEntity({
    required this.label,
    required this.file,
    this.isDefault = false,
    this.headers = const {},
  });
}
