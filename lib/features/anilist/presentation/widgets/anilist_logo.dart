import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';

/// The AniList mark.
///
/// Drawn from `assets/icons/anilist.svg`, which is a reconstruction of the
/// official logo rather than the file from AniList's brand kit. Dropping the
/// real SVG in at that path replaces it everywhere with no code change.
class AnilistLogo extends StatelessWidget {
  const AnilistLogo({super.key, this.size = 20, this.color = kAnilistBlue});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/anilist.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

/// The mark on its brand-blue tile, for places that need a service badge —
/// a settings row, an empty state, an account card.
class AnilistLogoBadge extends StatelessWidget {
  const AnilistLogoBadge({super.key, this.size = 44, this.radius = 12});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kAnilistBlue, kAnilistBlueDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: kAnilistBlue.withValues(alpha: 0.3),
            blurRadius: size * 0.4,
            spreadRadius: -size * 0.08,
          ),
        ],
      ),
      child: Center(
        child: AnilistLogo(size: size * 0.52, color: Colors.white),
      ),
    );
  }
}
