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
    super.localProxy,
    super.requestTransform,
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
      localProxy: _parseDynamicMap(json['localProxy']),
      requestTransform: _parseDynamicMap(json['requestTransform']),
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

  static Map<String, dynamic> _parseDynamicMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (k is String) out[k] = _normalizeJsonValue(v);
    });
    return out;
  }

  static dynamic _normalizeJsonValue(dynamic value) {
    if (value is Map) return _parseDynamicMap(value);
    if (value is List) {
      return value.map(_normalizeJsonValue).toList(growable: false);
    }
    return value;
  }
}
