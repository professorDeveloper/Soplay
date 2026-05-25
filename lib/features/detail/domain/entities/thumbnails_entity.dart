class ThumbnailsEntity {
  final String type;
  final String? url;
  final String? template;
  final int? width;
  final int? height;
  final int? columns;
  final int? rows;

  const ThumbnailsEntity({
    required this.type,
    this.url,
    this.template,
    this.width,
    this.height,
    this.columns,
    this.rows,
  });

  bool get isVtt => type == 'vtt' && url != null && url!.isNotEmpty;

  bool get isStoryboard =>
      type == 'storyboard' &&
      template != null &&
      template!.isNotEmpty &&
      (columns ?? 0) > 0 &&
      (rows ?? 0) > 0 &&
      (width ?? 0) > 0 &&
      (height ?? 0) > 0;
}
