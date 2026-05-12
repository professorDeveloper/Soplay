import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';

class HomeRepositoryImp implements HomeRepository {
  final ProviderManager providerManager;

  const HomeRepositoryImp(this.providerManager);

  @override
  Future<Result<HomeDataEntity>> loadHome() => providerManager.getHome();

  @override
  Future<Result<List<GenreEntity>>> loadGenres() =>
      providerManager.getGenres();

  @override
  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) =>
      providerManager.loadViewAll(key: key, slug: slug, page: page);
}
