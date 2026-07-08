import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_remote_data_source.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/my_list/domain/repositories/my_list_repository.dart';

class MyListRepositoryImpl implements MyListRepository {
  const MyListRepositoryImpl(this.remote, this.local, this.hive);

  final MyListRemoteDataSource remote;
  final MyListLocalDataSource local;
  final HiveService hive;

  @override
  Future<Result<List<FavoriteEntity>>> getFavorites() async {
    if (!hive.isLoggedIn) {
      return Success(local.getAll());
    }
    try {
      final server = await remote.getFavorites();
      await local.upsertAll(server);
      return Success(local.getAll());
    } catch (_) {
      return Success(local.getAll());
    }
  }

  @override
  Future<Result<void>> addFavorite(FavoriteEntity entity) async {
    await local.add(entity, synced: false);
    if (hive.isLoggedIn) {
      try {
        await remote.addFavorite(
          provider: entity.provider,
          contentUrl: entity.contentUrl,
          title: entity.title,
          thumbnail: entity.thumbnail,
        );
        await local.markSynced(entity.contentUrl);
      } catch (_) {}
    }
    return Success<void>(null);
  }

  @override
  Future<Result<void>> removeFavorite(String contentUrl) async {
    await local.removeByUrl(contentUrl);
    if (hive.isLoggedIn) {
      try {
        await remote.removeFavorite(contentUrl);
      } catch (_) {}
    }
    return Success<void>(null);
  }

  @override
  Future<void> syncAfterLogin() async {
    if (!hive.isLoggedIn) return;
    try {
      final server = await remote.getFavorites();
      bool existsOnServer(FavoriteModel candidate) {
        for (final s in server) {
          if (s.provider == candidate.provider &&
              s.contentUrl == candidate.contentUrl) {
            return true;
          }
        }
        for (final s in server) {
          if (s.contentUrl == candidate.contentUrl) return true;
        }
        return false;
      }

      for (final item in local.getAll()) {
        if (existsOnServer(item)) continue;
        try {
          await remote.addFavorite(
            provider: item.provider,
            contentUrl: item.contentUrl,
            title: item.title,
            thumbnail: item.thumbnail,
          );
          await local.markSynced(item.contentUrl);
        } catch (_) {}
      }
      await local.upsertAll(server);
    } catch (_) {}
  }
}
