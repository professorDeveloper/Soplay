import 'extractor_entity.dart';

class ExtractorModel extends ExtractorEntity {
  const ExtractorModel({
    required super.name,
    required super.version,
    required super.scope,
    required super.url,
  });

  factory ExtractorModel.fromJson(Map<String, dynamic> json) {
    return ExtractorModel(
      name: json['name'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      scope: json['scope'] as String? ?? 'resolveMedia',
      url: json['url'] as String? ?? '',
    );
  }
}
