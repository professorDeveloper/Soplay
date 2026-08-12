import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/my_list/domain/repositories/my_list_repository.dart';

class RemoveFavoriteUseCase {
  const RemoveFavoriteUseCase(this.repository);

  final MyListRepository repository;

  Future<Result<void>> call(String contentUrl) =>
      repository.removeFavorite(contentUrl);
}
