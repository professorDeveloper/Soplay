import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// What the seasons of a year are called, and which one a month falls in.
({String season, int year}) _currentSeason([DateTime? at]) {
  final now = at ?? DateTime.now();
  final season = switch (now.month) {
    12 || 1 || 2 => 'WINTER',
    3 || 4 || 5 => 'SPRING',
    6 || 7 || 8 => 'SUMMER',
    _ => 'FALL',
  };
  // December belongs to the winter season of the NEXT year, which is how
  // AniList files it — asking for WINTER of this year in December returns the
  // season that ended eleven months ago.
  final year = now.month == 12 ? now.year + 1 : now.year;
  return (season: season, year: year);
}

enum _Shelf { trending, season, popular, upcoming }

/// Discovery on AniList.
///
/// The library only ever showed your own list, so there was nothing in the app
/// that answered "what should I watch". This is that half — and it ends in
/// "find it in sources", because discovering something you then cannot open is
/// a dead end.
class AnilistBrowsePage extends StatefulWidget {
  const AnilistBrowsePage({super.key});

  @override
  State<AnilistBrowsePage> createState() => _AnilistBrowsePageState();
}

class _AnilistBrowsePageState extends State<AnilistBrowsePage> {
  final AnilistService _service = getIt<AnilistService>();

  _Shelf _shelf = _Shelf.trending;
  final Map<_Shelf, List<AnilistMedia>> _cache = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(_shelf);
  }

  Future<void> _load(_Shelf shelf, {bool force = false}) async {
    if (!force && _cache.containsKey(shelf)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final season = _currentSeason();
      final media = await _service.api.browse(
        sort: switch (shelf) {
          _Shelf.trending => 'TRENDING_DESC',
          _Shelf.popular => 'POPULARITY_DESC',
          _Shelf.season => 'POPULARITY_DESC',
          _Shelf.upcoming => 'POPULARITY_DESC',
        },
        season: shelf == _Shelf.season ? season.season : null,
        seasonYear: shelf == _Shelf.season ? season.year : null,
        status: shelf == _Shelf.upcoming ? 'NOT_YET_RELEASED' : null,
      );
      if (!mounted) return;
      setState(() {
        _cache[shelf] = media;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AnilistException ? e.message : 'anilist.browse_failed'.tr();
      });
    }
  }

  String _label(_Shelf shelf) => switch (shelf) {
    _Shelf.trending => 'anilist.browse_trending'.tr(),
    _Shelf.season => 'anilist.browse_season'.tr(),
    _Shelf.popular => 'anilist.browse_popular'.tr(),
    _Shelf.upcoming => 'anilist.browse_upcoming'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final items = _cache[_shelf] ?? const <AnilistMedia>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Row(
          children: [
            const AnilistLogo(size: 20),
            const SizedBox(width: 9),
            Text(
              'anilist.browse_title'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _Shelf.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final shelf = _Shelf.values[i];
                  final active = shelf == _shelf;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _shelf = shelf);
                      _load(shelf);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? kAnilistBlue.withValues(alpha: 0.16)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active ? kAnilistBlue : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        _label(shelf),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: active ? kAnilistBlue : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(child: _body(items)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<AnilistMedia> items) {
    if (_loading && items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: kAnilistBlue, strokeWidth: 2.5),
      );
    }
    if (_error != null && items.isEmpty) {
      return _Message(
        text: _error!,
        onRetry: () => _load(_shelf, force: true),
      );
    }
    if (items.isEmpty) {
      return _Message(text: 'anilist.browse_empty'.tr());
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 6 : (width >= 620 ? 5 : 3);

    return RefreshIndicator(
      color: kAnilistBlue,
      backgroundColor: AppColors.surface,
      onRefresh: () => _load(_shelf, force: true),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          // Poster plus two lines of caption.
          childAspectRatio: 0.5,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _MediaCard(
          media: items[i],
          onTap: () => _openSheet(items[i]),
        ),
      ),
    );
  }

  void _openSheet(AnilistMedia media) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MediaSheet(media: media),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.media, required this.onTap});

  final AnilistMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title =
        media.englishTitle ?? media.romajiTitle ?? media.nativeTitle ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnilistCover(url: media.coverImage, radius: 10),
                ),
                if (media.averageScore != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${media.averageScore}%',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What one title is, and the one thing worth doing about it.
class _MediaSheet extends StatelessWidget {
  const _MediaSheet({required this.media});

  final AnilistMedia media;

  @override
  Widget build(BuildContext context) {
    final title =
        media.englishTitle ?? media.romajiTitle ?? media.nativeTitle ?? '';
    final description = (media.description ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnilistCover(url: media.coverImage, width: 92, radius: 10),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (media.format != null) AnilistChip(label: media.format!),
                        if (media.seasonYear != null)
                          AnilistChip(label: '${media.seasonYear}'),
                        if (media.episodes != null)
                          AnilistChip(
                            label: 'anilist.episodes_count'.tr(
                              namedArgs: {'count': '${media.episodes}'},
                            ),
                          ),
                        if (media.averageScore != null)
                          AnilistChip(label: '${media.averageScore}%'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          // The bridge. Discovering something you cannot then open is a dead
          // end, and the source apps know nothing about AniList ids — the title
          // is what crosses.
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/cross-search', extra: title);
              },
              icon: const Icon(Icons.travel_explore_rounded, size: 19),
              label: Text('anilist.find_in_sources'.tr()),
            ),
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.explore_off_rounded,
              size: 46,
              color: AppColors.textHint.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onRetry,
                child: Text('anilist.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
