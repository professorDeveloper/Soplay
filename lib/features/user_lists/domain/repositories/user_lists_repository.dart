import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';

/// Read/write access to the user-curated lists.
///
/// Every method takes the [UserListKind] rather than existing once per list, so
/// the UI can render a tab per enum value with no per-list branching.
abstract class UserListsRepository {
  Future<Result<List<FavoriteEntity>>> getList(UserListKind kind);

  Future<Result<void>> add(UserListKind kind, FavoriteEntity entity);

  Future<Result<void>> remove(UserListKind kind, String contentUrl);

  /// Whether [contentUrl] is already in [kind] — drives the detail page's
  /// button state. Answered from the cache so it never blocks a page render.
  bool contains(UserListKind kind, String contentUrl);
}
