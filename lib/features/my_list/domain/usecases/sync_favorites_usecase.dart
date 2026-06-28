import 'package:soplay/features/my_list/domain/repositories/my_list_repository.dart';

class SyncFavoritesUseCase {
  final MyListRepository repository;

  const SyncFavoritesUseCase(this.repository);

  Future<void> call() => repository.syncAfterLogin();
}
