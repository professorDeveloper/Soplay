import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One live channel.
@immutable
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.country = '',
    this.language = '',
    this.category = '',
  });

  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String country;
  final String language;

  /// Filled in from the group it arrived in, so a channel carries its own
  /// category once it is out of the list.
  final String category;

  LiveChannel withCategory(String value) => LiveChannel(
    id: id,
    name: name,
    streamUrl: streamUrl,
    logoUrl: logoUrl,
    country: country,
    language: language,
    category: value,
  );

  static LiveChannel? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final url = json['streamUrl']?.toString();
    final name = json['name']?.toString();
    if (id == null || url == null || url.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return LiveChannel(
      id: id,
      name: name,
      streamUrl: url,
      logoUrl: (json['logoUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['logoUrl'] as String,
      country: json['country']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
    );
  }
}

@immutable
class LiveCategory {
  const LiveCategory({required this.name, required this.channels});

  final String name;
  final List<LiveChannel> channels;
}

/// The live TV line-up.
///
/// Grouped by the server rather than here: the TV app reads the same endpoint,
/// and two clients each applying their own grouping rules is two sets of rules
/// that drift.
class LiveTvService {
  const LiveTvService({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<LiveCategory>> lineup() async {
    final response = await _dio.get('/channels');
    final categories = (response.data as Map?)?['categories'];
    if (categories is! List) return const [];

    final out = <LiveCategory>[];
    for (final raw in categories.whereType<Map>()) {
      final name = raw['name']?.toString() ?? 'general';
      final list = raw['channels'];
      if (list is! List) continue;
      final channels = list
          .whereType<Map>()
          .map((e) => LiveChannel.fromJson(e.cast<String, dynamic>()))
          .whereType<LiveChannel>()
          .map((c) => c.withCategory(name))
          .toList(growable: false);
      if (channels.isNotEmpty) {
        out.add(LiveCategory(name: name, channels: channels));
      }
    }
    return out;
  }
}
