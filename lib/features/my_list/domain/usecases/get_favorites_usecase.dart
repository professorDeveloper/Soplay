import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/my_list/domain/entities/favorite_entity.dart';
import 'package:riasdxd/features/my_list/domain/repositories/my_list_repository.dart';

class GetFavoritesUseCase {
  final MyListRepository repository;

  const GetFavoritesUseCase(this.repository);

  Future<Result<List<FavoriteEntity>>> call() => repository.getFavorites();
}
