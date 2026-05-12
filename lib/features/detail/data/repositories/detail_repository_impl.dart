import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';

class DetailRepositoryImpl implements DetailRepository {
  final ProviderManager providerManager;

  const DetailRepositoryImpl(this.providerManager);

  @override
  Future<Result<DetailEntity>> getDetail(
    String contentUrl, {
    String? provider,
  }) =>
      providerManager.getDetail(contentUrl, provider: provider);

  @override
  Future<Result<PlaybackEntity>> getEpisodes(
    String contentUrl, {
    int page = 1,
    int size = 100,
    String sort = 'asc',
    String? provider,
  }) =>
      providerManager.getEpisodes(
        contentUrl,
        page: page,
        size: size,
        sort: sort,
        provider: provider,
      );

  @override
  Future<Result<MediaResolveEntity>> resolveMedia({
    required String ref,
    required String provider,
    String? lang,
  }) =>
      providerManager.resolveMedia(ref: ref, provider: provider, lang: lang);
}
