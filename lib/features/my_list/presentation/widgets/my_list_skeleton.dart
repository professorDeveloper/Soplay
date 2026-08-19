import 'package:flutter/material.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/my_list/presentation/widgets/favorite_card.dart';

class MyListSkeleton extends StatelessWidget {
  const MyListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Same insets as the loaded grid, so the last row clears the floating nav
    // bar and nothing shifts sideways when the real cards replace these.
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.paddingOf(context).bottom + 96,
      ),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 142,
          mainAxisSpacing: 16,
          crossAxisSpacing: 10,
          childAspectRatio: 0.56,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, _) => const _SkeletonCard(),
          childCount: 9,
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const ShimmerWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: HomeSkeletonBox(
              width: double.infinity,
              height: 1,
              radius: 10,
            ),
          ),
          SizedBox(height: 7),
          // Caption boxes reserve the same space FavoriteCard does, so the
          // poster does not resize when the real cards replace these.
          FixedTextLines(
            fontSize: FavoriteCard.titleFontSize,
            lineHeight: FavoriteCard.titleLineHeight,
            lines: 2,
            child: Align(
              alignment: Alignment.topLeft,
              child: HomeSkeletonBox(
                width: double.infinity,
                height: 12,
                radius: 4,
              ),
            ),
          ),
          SizedBox(height: FavoriteCard.metaGap),
          FixedTextLines(
            fontSize: FavoriteCard.metaFontSize,
            lineHeight: FavoriteCard.metaLineHeight,
            child: Align(
              alignment: Alignment.topLeft,
              child: HomeSkeletonBox(width: 72, height: 10, radius: 4),
            ),
          ),
        ],
      ),
    );
  }
}
