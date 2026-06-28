import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';

class FavoriteModel extends FavoriteEntity {
  const FavoriteModel({
    required super.provider,
    required super.contentUrl,
    required super.title,
    required super.thumbnail,
    super.description,
    this.addedAt = 0,
    this.synced = false,
  });

  final int addedAt;

  /// Whether this favorite is known to exist on the server/account.
  ///
  /// `true`  → saved to the user's account (synced).
  /// `false` → local-only (added while logged out, or not yet pushed).
  final bool synced;

  factory FavoriteModel.fromJson(Map<String, dynamic> json) => FavoriteModel(
    provider: json['provider'] as String? ?? '',
    contentUrl: json['contentUrl'] as String? ?? '',
    title: json['title'] as String? ?? '',
    thumbnail: json['thumbnail'] as String? ?? '',
    description: json['description'] as String? ?? '',
    addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
    synced: json['synced'] == true,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'contentUrl': contentUrl,
    'title': title,
    'thumbnail': thumbnail,
    'description': description,
    'addedAt': addedAt,
    'synced': synced,
  };
}
