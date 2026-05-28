import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

class VideoSourceModel extends VideoSourceEntity {
  const VideoSourceModel({
    required super.quality,
    required super.videoUrl,
    required super.isDefault,
    required super.accessible,
    super.useLocalProxy,
    super.type,
    super.headers,
  });

  factory VideoSourceModel.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['type'] as String?;
    return VideoSourceModel(
      quality: json['quality'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      accessible: json['accessible'] as bool? ?? false,
      useLocalProxy: json['useLocalProxy'] as bool? ?? false,
      type: typeRaw == null || typeRaw.isEmpty ? null : typeRaw.toLowerCase(),
      headers: _parseHeaders(json['headers']),
    );
  }

  static Map<String, String> _parseHeaders(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v != null) out[k] = v.toString();
    });
    return out;
  }
}
