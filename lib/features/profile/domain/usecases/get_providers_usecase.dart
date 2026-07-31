import 'package:soplay/core/error/result.dart';
import '../entities/providers_snapshot.dart';
import '../repositories/provider_repository.dart';

class GetProvidersUseCase {
  final ProviderRepository repository;

  const GetProvidersUseCase(this.repository);

  Future<Result<ProvidersSnapshot>> call() => repository.getProviders();
}
