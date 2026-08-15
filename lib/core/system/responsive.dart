import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/tv/tv_focusable.dart';

import 'platform_utils.dart';

export 'platform_utils.dart';

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

class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({super.key, required this.child, this.maxWidth = 1040});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class HoverTap extends StatefulWidget {
  const HoverTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.behavior = HitTestBehavior.opaque,
    this.scale = 1.04,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final VoidCallback? onSecondaryTap;
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
    // Android TV. Off desktop this widget resolves to a bare GestureDetector,
    // which CANNOT take focus — so on a television every card wrapped in a
    // HoverTap (posters, history rows, genre tiles, ...) was unreachable by the
    // D-pad: the remote could move around the nav rail but never into the
    // content. TvFocusable is the same tap handling plus a focus node, a ring
    // and scroll-into-view.
    //
    // Placed BEFORE the desktop branch and gated on isTvPlatform, which is
    // false on every phone, tablet and desktop — those keep the exact two paths
    // below, unchanged.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: widget.onTap,
        onLongPressed: widget.onLongPress,
        behavior: widget.behavior,
        scale: widget.scale,
        child: widget.child,
      );
    }
    final gesture = GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onSecondaryTap,
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

class DesktopRefreshButton extends StatefulWidget {
  const DesktopRefreshButton({
    super.key,
    required this.onRefresh,
    this.color,
    this.tooltip,
    this.spinning = false,
  });

  final VoidCallback onRefresh;
  final Color? color;
  final String? tooltip;
  final bool spinning;

  @override
  State<DesktopRefreshButton> createState() => _DesktopRefreshButtonState();
}

class _DesktopRefreshButtonState extends State<DesktopRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant DesktopRefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.spinning && old.spinning) {
      _c.animateTo(1, duration: const Duration(milliseconds: 300)).then((_) {
        if (mounted) _c.reset();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    if (!widget.spinning) {
      _c.forward(from: 0);
    }
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return const SizedBox.shrink();
    return IconButton(
      tooltip: widget.tooltip ?? 'desktop.refresh'.tr(),
      onPressed: _tap,
      icon: RotationTransition(
        turns: _c.drive(CurveTween(curve: Curves.easeInOut)),
        child: Icon(Icons.refresh_rounded, color: widget.color),
      ),
    );
  }
}

/// Puts D-pad focus inside the sheet it wraps.
///
/// A modal route does not move focus into itself. On a phone that is invisible —
/// the next interaction is a tap. On a television it is the whole bug: the sheet
/// appears, focus is still on the control *behind* it, and the first few remote
/// presses either do nothing or drive the player underneath. Every "the settings
/// menu opens but the remote is dead" report traces back to this.
///
/// Runs after the first frame because the route's subtree — and therefore its
/// focusable descendants — does not exist yet during build. If a descendant
/// declared `autofocus` (the selected row, typically) it has already claimed
/// focus by then and this is a no-op, which is exactly the desired precedence:
/// land on the current value, not the first item.
class _TvFocusEntry extends StatefulWidget {
  const _TvFocusEntry({required this.child});

  final Widget child;

  @override
  State<_TvFocusEntry> createState() => _TvFocusEntryState();
}

class _TvFocusEntryState extends State<_TvFocusEntry> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'tvModal');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scope.focusedChild != null) return; // an autofocus already won
      // nextFocus() from the scope lands on its first focusable descendant.
      _scope.nextFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The traversal group keeps arrow keys inside the sheet, so the D-pad
    // cannot wander back onto the player controls behind the barrier.
    return FocusScope(
      node: _scope,
      child: FocusTraversalGroup(child: widget.child),
    );
  }
}

Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  bool showDragHandle = false,
  double desktopMaxWidth = 460,
  double tvMaxWidth = 620,
}) {
  // Television: a centred dialog, not a bottom sheet.
  //
  // A bottom sheet is a thumb affordance — it hugs the edge furthest from the
  // eye line on a 10-foot screen, and its width is set by the screen, so on a
  // TV it renders as a short, very wide strip. The same content as a centred
  // panel reads correctly and, more importantly, gives the remote one obvious
  // place to be.
  if (isTvPlatform) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => _TvFocusEntry(
        child: Dialog(
          backgroundColor: backgroundColor,
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 48,
            vertical: 32,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tvMaxWidth,
              // Overscan-safe: TVs crop the outer few percent of the panel.
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
            ),
            child: SingleChildScrollView(child: builder(ctx)),
          ),
        ),
      ),
    );
  }
  if (isDesktopPlatform) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: backgroundColor,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktopMaxWidth,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
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
