import 'package:dio/dio.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';

/// Transport for `/auth/lists/<kind>`.
///
/// Deliberately parameterised by [UserListKind] rather than one method per
/// list: the server implements both lists through a single handler, and mirroring
/// that here keeps the two ends from drifting apart.
///
/// Items reuse [FavoriteModel] — the server returns the same
/// provider/contentUrl/title/thumbnail shape for lists as for favorites, so a
/// parallel model would be duplication with an extra chance to disagree. The
/// server's extra `addedAt` is ignored: nothing in the UI orders by it (the list
/// already arrives newest-first).
class UserListsRemoteDataSource {
  const UserListsRemoteDataSource({required this.dio});

  final Dio dio;

  Future<List<FavoriteModel>> getList(UserListKind kind) async {
    final response = await dio.get('/auth/lists/${kind.slug}');
    final data = response.data;
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => FavoriteModel.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.contentUrl.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> add(
    UserListKind kind, {
    required String provider,
    required String contentUrl,
    required String title,
    required String thumbnail,
  }) async {
    await dio.post(
      '/auth/lists/${kind.slug}',
      data: {
        'provider': provider,
        'contentUrl': contentUrl,
        'title': title,
        'thumbnail': thumbnail,
      },
    );
  }

  Future<void> remove(UserListKind kind, String contentUrl) async {
    await dio.delete(
      '/auth/lists/${kind.slug}',
      data: {'contentUrl': contentUrl},
    );
  }
}
