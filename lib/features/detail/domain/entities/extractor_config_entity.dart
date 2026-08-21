class ExtractorConfigEntity {
  final String mode;
  final String hostPattern;
  final List<String> urlPatterns;
  final List<String> captureHeaders;

  /// Ad/analytics hosts to swallow so the page settles and no ad creative is
  /// mistaken for the feature. Server-supplied, on top of the extractor's own
  /// baseline list — the app must not need to know which site it is talking to.
  final List<String> blockHosts;
  final int timeoutMs;
  final String? loginUrl;
  final String playType;

  const ExtractorConfigEntity({
    required this.hostPattern,
    required this.urlPatterns,
    this.mode = 'shouldInterceptRequest',
    this.captureHeaders = const [],
    this.blockHosts = const [],
    this.timeoutMs = 20000,
    this.loginUrl,
    this.playType = 'hls',
  });
}
