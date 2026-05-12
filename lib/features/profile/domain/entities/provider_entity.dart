import 'package:soplay/core/extractor/extractor_entity.dart';

class ProviderEntity {
  final String id;
  final String name;
  final String image;
  final String url;
  final String description;
  final List<String> domains;
  final String mode; // "server" | "hybrid" | "client"
  final ExtractorEntity? extractor;

  const ProviderEntity({
    required this.id,
    required this.name,
    required this.image,
    required this.url,
    required this.description,
    required this.domains,
    this.mode = 'server',
    this.extractor,
  });
}
