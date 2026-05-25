import 'package:soplay/features/detail/domain/entities/thumbnails_entity.dart';

class ThumbnailsModel extends ThumbnailsEntity {
  const ThumbnailsModel({
    required super.type,
    super.url,
    super.template,
    super.width,
    super.height,
    super.columns,
    super.rows,
  });

  static ThumbnailsEntity? fromJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      if (raw.isEmpty) return null;
      return ThumbnailsModel(type: 'vtt', url: raw);
    }
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    final type = (json['type'] as String?)?.toLowerCase() ?? 'vtt';
    final url = json['url'] as String?;
    final template = json['template'] as String?;
    final model = ThumbnailsModel(
      type: type,
      url: url == null || url.isEmpty ? null : url,
      template: template == null || template.isEmpty ? null : template,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      columns: (json['columns'] as num?)?.toInt(),
      rows: (json['rows'] as num?)?.toInt(),
    );
    if (!model.isVtt && !model.isStoryboard) return null;
    return model;
  }
}
