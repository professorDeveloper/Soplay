import 'package:soplay/core/extractor/extractor_model.dart';
import '../../domain/entities/provider_entity.dart';

class ProviderModel extends ProviderEntity {
  const ProviderModel({
    required super.id,
    required super.name,
    required super.image,
    required super.url,
    required super.description,
    required super.domains,
    super.mode,
    super.extractor,
  });

  factory ProviderModel.fromJson(Map<String, dynamic> json) {
    final id =
        json['id'] as String? ??
        json['_id'] as String? ??
        json['slug'] as String? ??
        '';
    final name = json['name'] as String? ?? id;

    final extractorJson = json['extractor'] as Map<String, dynamic>?;

    return ProviderModel(
      id: id,
      name: name,
      image: json['image'] as String? ?? '',
      url: json['url'] as String? ?? '',
      description: json['description'] as String? ?? '',
      domains: (json['domains'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      mode: json['mode'] as String? ?? 'server',
      extractor: extractorJson != null
          ? ExtractorModel.fromJson(extractorJson)
          : null,
    );
  }
}
