class VideoSourceEntity {
  final String quality;
  final String videoUrl;
  final bool isDefault;
  final bool accessible;
  final bool useLocalProxy;
  final String? type;
  final Map<String, String> headers;

  const VideoSourceEntity({
    required this.quality,
    required this.videoUrl,
    required this.isDefault,
    required this.accessible,
    this.useLocalProxy = false,
    this.type,
    this.headers = const {},
  });
}
