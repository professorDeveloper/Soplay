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
