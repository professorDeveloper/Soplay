import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/my_list/domain/entities/favorite_entity.dart';

abstract class MyListRepository {
  Future<Result<List<FavoriteEntity>>> getFavorites();
  Future<Result<void>> addFavorite(FavoriteEntity entity);
  Future<Result<void>> removeFavorite(String contentUrl);
  Future<void> syncAfterLogin();
}
