import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';

/// A single circular cast/character card used by the "Popular now" grid and the
/// as-you-type results grid. The profile photo carries a shared [Hero] tag so it
/// flies into the Actor Hero screen on tap. When [highlight] is non-empty the
/// matched substring of the name is bolded.
class CastCard extends StatelessWidget {
  const CastCard({
    super.key,
    required this.person,
    required this.onTap,
    this.highlight = '',
  });

  final CastPersonEntity person;
  final VoidCallback onTap;
  final String highlight;

  /// Stable Hero tag shared with [ActorHeroPage]'s profile photo.
  static String heroTag(CastPersonEntity p) => 'trivia-cast-${p.kind}-${p.id}';

  @override
  Widget build(BuildContext context) {
    final knownFor = person.knownFor
        .where((e) => e.trim().isNotEmpty)
        .take(2)
        .join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: heroTag(person),
            child: CastAvatar(url: person.profileUrl, name: person.name),
          ),
          const SizedBox(height: 9),
          _HighlightedName(name: person.name, query: highlight),
          if (knownFor.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              knownFor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular avatar with a subtle red ring + shimmer placeholder. Reused by the
/// cast grid and the top-fans strip.
class CastAvatar extends StatelessWidget {
  const CastAvatar({
    super.key,
    required this.url,
    required this.name,
    this.highlightRing = false,
  });

  final String url;
  final String name;
  final bool highlightRing;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: highlightRing
                ? const [AppColors.primaryLight, AppColors.primary]
                : [
                    AppColors.primary.withValues(alpha: 0.55),
                    AppColors.primary.withValues(alpha: 0.15),
                  ],
          ),
        ),
        child: ClipOval(
          child: ColoredBox(
            color: AppColors.surfaceVariant,
            child: _image(),
          ),
        ),
      ),
    );
  }

  Widget _image() {
    if (url.trim().isEmpty) return _fallback();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 140),
      placeholder: (_, _) =>
          const ShimmerWrapper(child: ColoredBox(color: Colors.white)),
      errorWidget: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            initial,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 34,
            ),
          ),
        ),
      ),
    );
  }
}

/// The name line, bolding the matched substring of [query] (case-insensitive).
class _HighlightedName extends StatelessWidget {
  const _HighlightedName({required this.name, required this.query});

  final String name;
  final String query;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );

    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: base,
      );
    }

    final lower = name.toLowerCase();
    final start = lower.indexOf(q);
    if (start < 0) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: base,
      );
    }
    final end = start + q.length;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: name.substring(0, start)),
          TextSpan(
            text: name.substring(start, end),
            style: const TextStyle(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w900,
            ),
          ),
          TextSpan(text: name.substring(end)),
        ],
      ),
    );
  }
}

/// Shimmer skeleton mirroring a [CastCard] for the loading grids.
class CastCardSkeleton extends StatelessWidget {
  const CastCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const ShimmerWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(height: 11),
          HomeSkeletonBox(width: 64, height: 11, radius: 4),
          SizedBox(height: 5),
          HomeSkeletonBox(width: 40, height: 9, radius: 4),
        ],
      ),
    );
  }
}
