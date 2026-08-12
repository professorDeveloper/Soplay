import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/home/domain/entities/home_data_entity.dart';
import 'package:riasdxd/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:riasdxd/features/search/domain/entities/genre_entity.dart';

abstract class HomeRepository {
  Future<Result<HomeDataEntity>> loadHome();

  Future<Result<List<GenreEntity>>> loadGenres();

  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  });
}
