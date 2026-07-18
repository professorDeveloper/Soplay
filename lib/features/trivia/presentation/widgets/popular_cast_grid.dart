import 'package:flutter/material.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/presentation/widgets/cast_card.dart';

/// A 3-column grid of circular [CastCard]s. Used for both the "Popular now"
/// grid (empty query) and the as-you-type results grid. Scrolls on its own so
/// the picker page can float a pinned glass search bar above it.
class PopularCastGrid extends StatelessWidget {
  const PopularCastGrid({
    super.key,
    required this.people,
    required this.onTapPerson,
    this.highlight = '',
    this.padding = kCastGridPadding,
    this.controller,
  });

  final List<CastPersonEntity> people;
  final void Function(CastPersonEntity person) onTapPerson;
  final String highlight;
  final EdgeInsets padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: _delegate,
      itemCount: people.length,
      itemBuilder: (context, i) {
        final person = people[i];
        return CastCard(
          person: person,
          highlight: highlight,
          onTap: () => onTapPerson(person),
        );
      },
    );
  }
}

/// Shimmer placeholder grid shown while popular/results load.
class CastGridSkeleton extends StatelessWidget {
  const CastGridSkeleton({
    super.key,
    this.itemCount = 12,
    this.padding = kCastGridPadding,
  });

  final int itemCount;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: _delegate,
      itemCount: itemCount,
      itemBuilder: (_, _) => const CastCardSkeleton(),
    );
  }
}

/// 12px gutter — the app's 3-column grid gutter (view-all, search, detail cast).
const EdgeInsets kCastGridPadding = EdgeInsets.fromLTRB(12, 8, 12, 24);

/// Tuned against the shipped people grid (`detail_cast_tab.dart`: 3 cols,
/// cross 8, main 14) rather than the old sparse 14/22/0.68.
///
/// On a 360-wide device: usable = 360 − 24 = 336, tile w = (336 − 16)/3 =
/// 106.67, tile h = 106.67 / 0.80 = 133.33, row pitch = 147.33 (was 169.06 —
/// 13% denser, and the avatar no longer scales with the tile).
///
/// Content at the owner's textScale 1.1: avatar 64 + gap 8 + name (2 × 12 ×
/// 1.1 × 1.2 = 31.68) + gap 2 + sub-label (10 × 1.1 × 1.2 = 13.2) = 118.88,
/// leaving 14.45 slack (10.8%) — above the 10% floor. At scale 1.0 the content
/// is 114.8, slack 18.53 (13.9%).
///
/// The ratio is 0.80 rather than 0.92 because the name wraps to two lines (a
/// one-line name at this tile width truncates people like "Victoria Pedretti").
const SliverGridDelegateWithFixedCrossAxisCount _delegate =
    SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  mainAxisSpacing: 14,
  crossAxisSpacing: 8,
  childAspectRatio: 0.80,
);
