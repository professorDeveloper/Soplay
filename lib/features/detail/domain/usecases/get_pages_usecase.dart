import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';

class GetPagesUseCase {
  final DetailRepository repository;
  const GetPagesUseCase(this.repository);

  Future<Result<MangaPagesEntity>> call({
    required String ref,
    required String provider,
  }) {
    return repository.getPages(ref: ref, provider: provider);
  }
}
