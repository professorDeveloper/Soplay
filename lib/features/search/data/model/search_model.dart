import 'package:soplay/features/home/data/models/movie_model.dart';

import '../../domain/entities/search_entity.dart';

class SearchModel extends SearchEntity {
  SearchModel({required super.provider, required super.items,
    required super.page, required super.totalPages
  });

  factory SearchModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SearchModel(
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      provider: json['provider'] as String? ?? '',
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => MovieModel.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const <MovieModel>[],
    );
  }
}
