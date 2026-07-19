import 'package:soplay/core/error/result.dart';
import '../entities/providers_snapshot.dart';

abstract class ProviderRepository {
  /// Fetches the provider list, falling back to the Hive cache when the
  /// backend is unreachable. Only fails when there is no cache either.
  Future<Result<ProvidersSnapshot>> getProviders();
}
