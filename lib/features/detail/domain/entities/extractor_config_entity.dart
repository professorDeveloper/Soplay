class ExtractorConfigEntity {
  final String mode;
  final String hostPattern;
  final List<String> urlPatterns;
  final List<String> captureHeaders;
  final int timeoutMs;
  final String? loginUrl;
  final String playType;

  const ExtractorConfigEntity({
    required this.hostPattern,
    required this.urlPatterns,
    this.mode = 'shouldInterceptRequest',
    this.captureHeaders = const [],
    this.timeoutMs = 20000,
    this.loginUrl,
    this.playType = 'hls',
  });
}
