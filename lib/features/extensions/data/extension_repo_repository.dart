import 'package:dio/dio.dart';

import 'package:riasdxd/features/extensions/data/extension_repo_defaults.dart';
import 'package:riasdxd/features/extensions/domain/entities/extension_repo_entity.dart';

/// Serves the "Recommended" lists for the sources pages.
///
/// Backend-first with a compiled-in fallback ([ExtensionRepoDefaults]): the list
/// is curated from the admin panel so a dead or migrated repo can be swapped
/// without an app release, but a backend outage must never leave the page blank
/// — that is exactly when a user is most likely to be re-adding sources.
///
/// Results are cached in memory for the process lifetime; the list changes on
/// the order of weeks and each sources page rebuilds often.
class ExtensionRepoRepository {
  ExtensionRepoRepository({required this.dio});

  final Dio dio;

  final Map<ExtensionRepoKind, List<ExtensionRepoEntity>> _cache = {};

  /// Recommended repos for [kind], newest curation first.
  ///
  /// [nsfwAllowed] gates 18+ repos; off by default to match the adult-sources
  /// preference used elsewhere in the app.
  Future<List<ExtensionRepoEntity>> recommended(
    ExtensionRepoKind kind, {
    bool nsfwAllowed = false,
  }) async {
    final cached = _cache[kind];
    if (cached != null) return _visible(cached, nsfwAllowed);

    List<ExtensionRepoEntity> list;
    try {
      final resp = await dio.get<dynamic>(
        '/extension-repos',
        queryParameters: {'kind': kind.wire},
      );
      final items = (resp.data is Map ? resp.data['items'] : null);
      list = items is List
          ? items
              .whereType<Map>()
              .map((e) => _fromJson(Map<String, dynamic>.from(e)))
              .whereType<ExtensionRepoEntity>()
              .toList()
          : const [];
    } catch (_) {
      list = const [];
    }

    // Empty is treated as "backend has nothing to say", not "the curated list is
    // intentionally empty" — a misconfigured deploy shouldn't hide every repo.
    if (list.isEmpty) list = ExtensionRepoDefaults.forKind(kind);

    _cache[kind] = list;
    return _visible(list, nsfwAllowed);
  }

  /// Drops the memory cache so the next read re-fetches. Used by pull-to-refresh.
  void invalidate() => _cache.clear();

  List<ExtensionRepoEntity> _visible(
    List<ExtensionRepoEntity> list,
    bool nsfwAllowed,
  ) =>
      nsfwAllowed ? list : list.where((r) => !r.nsfw).toList();

  ExtensionRepoEntity? _fromJson(Map<String, dynamic> json) {
    final kind = ExtensionRepoKind.parse(json['kind'] as String?);
    final url = (json['url'] as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim() ?? '';
    if (kind == null || url.isEmpty || name.isEmpty) return null;
    return ExtensionRepoEntity(
      kind: kind,
      name: name,
      description: (json['description'] as String?) ?? '',
      url: url,
      animeUrl: (json['animeUrl'] as String?)?.trim(),
      novelUrl: (json['novelUrl'] as String?)?.trim(),
      iconUrl: (json['iconUrl'] as String?)?.trim(),
      badge: (json['badge'] as String?)?.trim(),
      nsfw: json['nsfw'] == true,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}
