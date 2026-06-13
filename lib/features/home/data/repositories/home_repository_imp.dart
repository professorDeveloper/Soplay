import 'package:dio/dio.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/js/js_runtime_service.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/home/data/models/home_data_model.dart';
import 'package:soplay/features/home/data/models/view_all_paging_model.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';

import '../../domain/entities/home_data_entity.dart';

class HomeRepositoryImp implements HomeRepository {
  final HomeDataSource dataSource;
  final JsRuntimeService? jsRuntime;
  final HiveService? hive;

  const HomeRepositoryImp(this.dataSource, {this.jsRuntime, this.hive});

  String? get _currentProvider {
    final id = hive?.getCurrentProvider();
    return (id == null || id.isEmpty) ? null : id;
  }

  @override
  Future<Result<HomeDataEntity>> loadHome() async {
    final js = jsRuntime;
    final provider = _currentProvider;
    if (provider != null && provider.startsWith('cs:')) {
      try {
        final map = await CloudStreamChannel.getMainPage(provider.substring(3));
        if (map.isNotEmpty) return Success(HomeDataModel.fromJson(map));
        return Failure(Exception('CloudStream: home not found'));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.getMainPage(provider.substring(3));
        if (map.isNotEmpty) return Success(HomeDataModel.fromJson(map));
        return Failure(Exception('Aniyomi: home not found'));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (js != null && provider != null) {
      try {
        final map = await js.tryGetHome(provider);
        if (map != null) return Success(HomeDataModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }

    try {
      final data = await dataSource.loadHome();
      return Success(data);
    } on DioException catch (e) {
      final raw = e.response?.data;
      final message =
          (raw is Map ? raw['message'] : null) ??
          e.message ??
          'Xatolik yuz berdi';
      return Failure(Exception(message.toString()));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<ViewAllPagingEntity>> loadViewAll({
    required String key,
    required String slug,
    int page = 1,
  }) async {
    final js = jsRuntime;
    final provider = _currentProvider;
    if (provider != null && provider.startsWith('cs:')) {
      try {
        // slug = the section's MainPageData.data → fetch just that section.
        final map = await CloudStreamChannel.getSection(
          provider.substring(3),
          slug,
          page: page,
        );
        return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (provider != null && provider.startsWith('an:')) {
      try {
        final map = await AniyomiChannel.getSection(
          provider.substring(3),
          slug,
          page: page,
        );
        return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }
    if (js != null && provider != null && key == 'category') {
      try {
        final map = await js.tryGetCategory(provider, slug, page);
        if (map != null) return Success(ViewAllPagingModel.fromJson(map));
      } catch (e) {
        return Failure(Exception(e.toString()));
      }
    }

    try {
      final data = await dataSource.loadViewAll(
        slug: slug,
        page: page,
        type: key,
      );
      return Success(data);
    } on DioException catch (e) {
      final raw = e.response?.data;
      final message =
          (raw is Map ? raw['message'] : null) ??
          e.message ??
          'Xatolik yuz berdi';
      return Failure(Exception(message.toString()));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<List<GenreEntity>>> loadGenres() async {
    // CloudStream "genres" = the provider's mainPage categories (native side).
    final provider = _currentProvider;
    if (provider != null && provider.startsWith('cs:')) {
      try {
        final list = await CloudStreamChannel.getGenres(provider.substring(3));
        final genres = list
            .whereType<Map>()
            .map((e) => GenreModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return Success(genres);
      } catch (_) {
        return const Success(<GenreEntity>[]);
      }
    }
    if (provider != null && provider.startsWith('an:')) {
      try {
        final list = await AniyomiChannel.getGenres(provider.substring(3));
        final genres = list
            .whereType<Map>()
            .map((e) => GenreModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return Success(genres);
      } catch (_) {
        return const Success(<GenreEntity>[]);
      }
    }
    try {
      final data = await dataSource.loadGenres();
      return Success(data);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
