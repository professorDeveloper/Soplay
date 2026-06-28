import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import '../entities/detail_entity.dart';
import '../entities/media_resolve_entity.dart';
import '../entities/playback_entity.dart';

abstract class DetailRepository {
  Future<Result<DetailEntity>> getDetail(String contentUrl, {String? provider});
  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page,
    int size,
    String sort,
    String? provider,
  });
  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  });

  /// Resolves a manga chapter ([ref] = the chapter's mediaRef) to its image
  /// pages. Only supported for `mn:` (manga) providers.
  Future<Result<MangaPagesEntity>> getPages({
    required String ref,
    required String provider,
  });
}
