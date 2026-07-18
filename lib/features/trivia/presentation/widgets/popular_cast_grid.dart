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
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
    this.itemCount = 9,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

const SliverGridDelegateWithFixedCrossAxisCount _delegate =
    SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  mainAxisSpacing: 22,
  crossAxisSpacing: 14,
  childAspectRatio: 0.68,
);
