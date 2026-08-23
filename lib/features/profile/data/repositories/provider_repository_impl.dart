import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import '../../domain/entities/providers_snapshot.dart';
import '../../domain/repositories/provider_repository.dart';
import '../datasources/provider_data_source.dart';
import '../models/provider_model.dart';

class ProviderRepositoryImpl implements ProviderRepository {
  final ProviderDataSource dataSource;
  final HiveService hiveService;

  const ProviderRepositoryImpl(this.dataSource, this.hiveService);

  @override
  Future<Result<ProvidersSnapshot>> getProviders() async {
    try {
      final providers = await dataSource.getProviders();
      // Only overwrite the cache with a list that actually has something in
      // it — a backend that answers 200 with an empty array would otherwise
      // wipe the only copy we have to fall back on.
      if (providers.isNotEmpty) {
        await hiveService.saveCachedProviders(
          providers.map((p) => p.toJson()).toList(),
        );
      }
      return Success(ProvidersSnapshot(providers: providers, fromCache: false));
    } catch (e) {
      final cached = _readCache();
      if (cached.isEmpty) return Failure(Exception(e.toString()));
      return Success(
        ProvidersSnapshot(
          providers: cached,
          fromCache: true,
          cachedAt: hiveService.getCachedProvidersAt(),
        ),
      );
    }
  }

  List<ProviderModel> _readCache() {
    try {
      return hiveService
          .getCachedProviders()
          .map(ProviderModel.fromJson)
          .where((p) => p.id.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
