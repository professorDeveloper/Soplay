import 'package:riasdxd/features/extensions/domain/entities/extension_repo_entity.dart';

/// Compiled-in fallback for the "Recommended" lists.
///
/// Used when the backend is unreachable or has no entries for a kind, so the
/// sources pages are never empty on a fresh install with no connectivity. The
/// backend list wins whenever it has anything for that kind — that is the point
/// of moving these server-side.
///
/// The urls here are the *current* ones as of this build. Notably the manga
/// entries point at `index.pb`: `yuzono/manga-repo` never published an
/// `index.min.json`, and Keiyoushi's is now a two-entry "Outdated App" stub, so
/// the old `.json` urls resolved to zero installable sources.
class ExtensionRepoDefaults {
  const ExtensionRepoDefaults._();

  static const List<ExtensionRepoEntity> all = [
    // --- CloudStream ------------------------------------------------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.cloudstream,
      name: 'Phisher Extensions',
      description: 'Large collection · movies, series & anime',
      url:
          'https://raw.githubusercontent.com/phisher98/cloudstream-extensions-phisher/refs/heads/builds/repo.json',
      order: 0,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.cloudstream,
      name: 'Redowan CloudStream',
      description: 'Popular providers · movies & series',
      url:
          'https://raw.githubusercontent.com/redowan99/Redowan-CloudStream/master/repo.json',
      order: 1,
    ),

    // --- Aniyomi (anime) --------------------------------------------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.aniyomi,
      name: 'Yuzono Anime',
      description: 'Largest collection · 270+ sources',
      url:
          'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
      badge: '270+',
      order: 0,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.aniyomi,
      name: 'Secozzi',
      description: 'Jellyfin · Stremio · Torbox',
      url:
          'https://raw.githubusercontent.com/Secozzi/aniyomi-extensions/repo/index.min.json',
      order: 1,
    ),

    // --- Manga ------------------------------------------------------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.manga,
      name: 'Yuzono Manga',
      description: 'Largest collection · 1300+ extensions',
      url: 'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.pb',
      badge: '1300+',
      order: 0,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.manga,
      name: 'Keiyoushi',
      description: 'Community manga / manhwa / webtoon sources',
      url: 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb',
      order: 1,
    ),

    // --- Mangayomi (JavaScript extensions — work on iOS too) --------------
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.mangayomi,
      name: 'Kodjodevf (official)',
      description: 'Manga & novels · official Mangayomi repo',
      url:
          'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
      novelUrl:
          'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/novel_index.json',
      order: 0,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.mangayomi,
      name: 'm2k3a',
      description: 'Manga · anime · novels',
      url:
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/index.json',
      animeUrl:
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
      novelUrl:
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/novel_index.json',
      order: 1,
    ),
    ExtensionRepoEntity(
      kind: ExtensionRepoKind.mangayomi,
      name: 'Swakshan',
      description: 'Anime-focused community sources',
      url:
          'https://raw.githubusercontent.com/Swakshan/mangayomi-swak-extensions/main/index.json',
      animeUrl:
          'https://raw.githubusercontent.com/Swakshan/mangayomi-swak-extensions/main/anime_index.json',
      order: 2,
    ),
  ];

  static List<ExtensionRepoEntity> forKind(ExtensionRepoKind kind) =>
      all.where((r) => r.kind == kind).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
}
