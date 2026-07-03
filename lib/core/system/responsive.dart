import 'package:flutter/material.dart';

import 'platform_utils.dart';

/// A grid delegate that keeps the existing fixed column count on **mobile**, but
/// on **desktop** scales the number of columns to the window width (so posters
/// don't become giant on a wide window). Mobile layout is unchanged.
SliverGridDelegate responsiveGridDelegate({
  required int mobileCrossAxisCount,
  required double childAspectRatio,
  double crossAxisSpacing = 8,
  double mainAxisSpacing = 8,
  double desktopMaxCrossAxisExtent = 160,
}) {
  if (isDesktopPlatform) {
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: desktopMaxCrossAxisExtent,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: mobileCrossAxisCount,
    childAspectRatio: childAspectRatio,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
  );
}

/// On **desktop**, centres its child within [maxWidth] so full-width content
/// (buttons, text, rows) doesn't stretch edge-to-edge on a wide window. On
/// **mobile** it is a pass-through (no change).
class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({super.key, required this.child, this.maxWidth = 1040});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    // topCenter (not Center): centre horizontally but keep the child top-aligned
    // so content in a min-height area isn't pushed to the vertical middle.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
