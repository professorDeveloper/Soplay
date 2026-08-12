import 'package:riasdxd/features/home/domain/entities/movie.dart';
import 'package:riasdxd/features/profile/domain/entities/provider_entity.dart';

/// How a provider is searched. Decides the dispatch path in [CrossSearchEngine].
enum ProviderKind {
  /// On-device extension host: Kotlin (`cs:` / `an:` / `mn:`) or the
  /// JavaScript runtime (`my:`). Both run entirely on the device and may need
  /// to fetch the extension itself before the first call, which is why they
  /// share the engine's longer per-provider budget.
  channel,

  /// On-device full-scope JS extractor.
  js,

  /// Backend (`/contents/search`) — provider-agnostic; collapses to one call.
  server,
}

/// Outcome of one provider's search leg.
enum ProviderSearchStatus { ok, empty, timeout, error }

/// A lightweight, UI-facing handle to a provider participating in cross-search.
class ProviderRef {
  const ProviderRef({
    required this.id,
    required this.name,
    required this.kind,
    this.image,
  });

  final String id;
  final String name;
  final String? image;
  final ProviderKind kind;

  static ProviderKind kindOf(String id, {required bool scopesAll}) {
    if (id.startsWith('cs:') ||
        id.startsWith('an:') ||
        id.startsWith('mn:') ||
        id.startsWith('my:')) {
      return ProviderKind.channel;
    }
    return scopesAll ? ProviderKind.js : ProviderKind.server;
  }

  factory ProviderRef.fromEntity(ProviderEntity p) => ProviderRef(
        id: p.id,
        name: p.name,
        image: p.image.isEmpty ? null : p.image,
        kind: kindOf(p.id, scopesAll: p.scopesAll),
      );
}

/// One provider's search result (may be empty / timed-out / errored).
class ProviderSearchResult {
  const ProviderSearchResult({
    required this.provider,
    required this.items,
    required this.status,
  });

  final ProviderRef provider;
  final List<MovieEntity> items;
  final ProviderSearchStatus status;

  bool get hasItems => items.isNotEmpty;
}
