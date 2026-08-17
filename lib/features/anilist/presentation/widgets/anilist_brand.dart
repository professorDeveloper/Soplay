import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';

/// AniList's own blue. Used only for AniList affordances, so a "connect" or
/// "tracked" badge is never mistaken for a Sozo-native action in red.
const Color kAnilistBlue = Color(0xFF02A9FF);
const Color kAnilistBlueDeep = Color(0xFF0073C4);

/// Cover art with a fixed 2:3 poster ratio.
///
/// The ratio is enforced rather than inherited from the image: AniList covers
/// vary by a few pixels, and a grid of almost-aligned posters reads as broken.
class AnilistCover extends StatelessWidget {
  const AnilistCover({
    super.key,
    required this.url,
    this.width,
    this.radius = 10,
  });

  final String? url;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = AspectRatio(
      aspectRatio: 2 / 3,
      child: (url == null || url!.isEmpty)
          ? const _CoverPlaceholder()
          : CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 180),
              placeholder: (_, _) => const _CoverPlaceholder(),
              errorWidget: (_, _, _) => const _CoverPlaceholder(),
            ),
    );
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
    return width == null ? clipped : SizedBox(width: width, child: clipped);
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(
          Icons.movie_creation_outlined,
          color: AppColors.textHint,
          size: 22,
        ),
      );
}

/// A small filled label — episode counts, formats, "tracked" markers.
class AnilistChip extends StatelessWidget {
  const AnilistChip({
    super.key,
    required this.label,
    this.icon,
    this.color = kAnilistBlue,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 8 : 7, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.32), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The rounded progress rail used on every entry card.
class AnilistProgressBar extends StatelessWidget {
  const AnilistProgressBar({super.key, required this.value, this.color = kAnilistBlue});

  /// 0..1, or null when the total is unknown — which renders a flat unfilled
  /// rail rather than an indeterminate animation that implies loading.
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value ?? 0),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 4,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

/// The block shown wherever a screen needs an AniList connection it does not
/// have. One widget so the message and the button never drift apart between
/// the library, the upcoming list and the title screen.
class AnilistConnectPrompt extends StatelessWidget {
  const AnilistConnectPrompt({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onConnect,
    this.busy = false,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onConnect;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [kAnilistBlue, kAnilistBlueDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAnilistBlue.withValues(alpha: 0.28),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.link_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: kAnilistBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
