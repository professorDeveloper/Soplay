import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/shorts/domain/entities/shorts_feed_result.dart';
import 'package:riasdxd/features/shorts/domain/repositories/shorts_repository.dart';

class GetShortsUseCase {
  const GetShortsUseCase(this.repository);

  final ShortsRepository repository;

  Future<Result<ShortsFeedResult>> call({
    String? cursor,
    String? query,
    int limit = 15,
  }) =>
      repository.getShortsFeed(cursor: cursor, query: query, limit: limit);
}
