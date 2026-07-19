import 'provider_entity.dart';

/// A provider list plus where it came from.
///
/// The distinction matters during a backend outage: a cached list is still
/// worth showing (the on-device plugins in it keep working) but the app must
/// not present it as fresh, and its server-backed entries cannot be used.
class ProvidersSnapshot {
  const ProvidersSnapshot({
    required this.providers,
    required this.fromCache,
    this.cachedAt,
  });

  final List<ProviderEntity> providers;

  /// True when the network call failed and this came out of Hive instead.
  final bool fromCache;

  /// When the cache was written. Null for a fresh list.
  final DateTime? cachedAt;
}
