import 'package:flutter/material.dart';

import 'platform_utils.dart';

// Re-export so importing this file also brings `isDesktopPlatform` in scope.
export 'platform_utils.dart';

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

/// Drop-in replacement for a tappable `GestureDetector` (same `onTap` / `child`
/// shape). On **desktop** it adds a pointer (hand) cursor and a subtle hover
/// scale; on **mobile** it behaves exactly like a plain `GestureDetector`.
class HoverTap extends StatefulWidget {
  const HoverTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior = HitTestBehavior.opaque,
    this.scale = 1.04,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior behavior;
  final double scale;
  final MouseCursor cursor;

  @override
  State<HoverTap> createState() => _HoverTapState();
}

class _HoverTapState extends State<HoverTap> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final gesture = GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: widget.behavior,
      child: widget.child,
    );
    if (!isDesktopPlatform) return gesture;
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: gesture,
      ),
    );
  }
}

/// Shows a pointer (hand) cursor over [child] on **desktop**; pass-through on
/// mobile. Use for tappables where a hover *scale* isn't wanted (buttons, rows).
class PointerRegion extends StatelessWidget {
  const PointerRegion({
    super.key,
    required this.child,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return MouseRegion(cursor: cursor, child: child);
  }
}

/// On **desktop** shows a centred [Dialog]; on **mobile** a modal bottom sheet.
/// The [builder]'s content should be a self-sizing column (works in both).
Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  bool showDragHandle = false,
  double desktopMaxWidth = 460,
}) {
  if (isDesktopPlatform) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: backgroundColor,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktopMaxWidth),
          child: SingleChildScrollView(child: builder(ctx)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    shape: shape,
    showDragHandle: showDragHandle,
    builder: builder,
  );
}
