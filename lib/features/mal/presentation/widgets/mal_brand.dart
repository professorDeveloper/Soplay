import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:flutter/material.dart';

/// MyAnimeList's own blue. Used only for MAL affordances, so a "connect" or
/// "tracked" badge is never mistaken for a Sozo-native action in red, nor for
/// an AniList one.
const Color kMalBlue = Color(0xFF2E51A2);
const Color kMalBlueDeep = Color(0xFF1F3A78);

/// The MyAnimeList mark.
///
/// Drawn rather than shipped as an asset: MAL's brand IS the wordmark on its
/// blue, so a tile and three letters reproduce it honestly at every size, and
/// `flutter_svg` does not render `<text>` reliably enough to do it in SVG
/// without converting the glyphs to paths first.
class MalLogo extends StatelessWidget {
  const MalLogo({super.key, this.size = 20, this.radius = 5});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kMalBlue,
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.12),
            child: Text(
              'MAL',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900,
                letterSpacing: -size * 0.012,
                height: 1,
              ),
            ),
          ),
        ),
      );
}

/// The label for a MAL status, translated.
///
/// A function rather than a map on the status class: the strings live in the
/// translation files, which cannot be reached from a const.
String malStatusLabel(String status) => switch (status) {
      MalStatus.watching => 'anilist.status_current'.tr(),
      MalStatus.completed => 'anilist.status_completed'.tr(),
      MalStatus.onHold => 'anilist.status_paused'.tr(),
      MalStatus.dropped => 'anilist.status_dropped'.tr(),
      MalStatus.planToWatch => 'anilist.status_planning'.tr(),
      _ => status,
    };

