import 'package:soplay/core/network/user_agent.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';

class ShimmerWrapper extends StatelessWidget {
  const ShimmerWrapper({super.key, required this.child});
  final Widget child;

  // Subtle, but not invisible: eleven levels of separation on a dark panel read
  // as a frozen screen rather than as loading, which is the one thing a skeleton
  // exists to avoid.
  static const _base = Color(0xFF1E1E1E);
  static const _highlight = Color(0xFF333333);

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: _base,
    highlightColor: _highlight,
    period: const Duration(milliseconds: 1650),
    child: child,
  );
}

class HomeNetworkImage extends StatelessWidget {
  const HomeNetworkImage({
    super.key,
    required this.url,
    required this.borderRadius,
    required this.placeholderIcon,
    this.fit = BoxFit.cover,
    this.headers,
  });

  final String? url;
  final BorderRadius borderRadius;
  final IconData placeholderIcon;
  final BoxFit fit;

  final Map<String, String>? headers;

  static Map<String, String>? _defaultHeaders(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return {
      'Referer': '${uri.scheme}://${uri.host}/',
      // Must be the app's one agent: a cf_clearance cookie is bound to the exact
      // agent that earned it, so a poster asking under a different one is
      // challenged and never loads.
      'User-Agent': kSozoUserAgent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: HomeImagePlaceholder(icon: placeholderIcon),
      );
    }

    if (_isLocalPath(imageUrl)) {
      final file = imageUrl.startsWith('file://')
          ? File(Uri.parse(imageUrl).toFilePath())
          : File(imageUrl);
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          file,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, _, _) =>
              HomeImagePlaceholder(icon: placeholderIcon),
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final w = (!isDesktopPlatform && constraints.maxWidth.isFinite)
              ? (constraints.maxWidth * dpr).round()
              : null;
          return Image.network(
            imageUrl,
            headers: headers ?? _defaultHeaders(imageUrl),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: (w != null && w > 0) ? w : null,
            filterQuality:
                isDesktopPlatform ? FilterQuality.medium : FilterQuality.low,
            errorBuilder: (_, _, _) =>
                HomeImagePlaceholder(icon: placeholderIcon),
            loadingBuilder: (_, child, chunk) => chunk == null
                ? child
                : HomeImagePlaceholder(icon: placeholderIcon),
          );
        },
      ),
    );
  }

  bool _isLocalPath(String value) {
    if (value.startsWith('file://')) return true;
    return value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }
}

class HomeImagePlaceholder extends StatelessWidget {
  const HomeImagePlaceholder({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Icon(icon, color: AppColors.textHint, size: 28),
        ),
      ),
    );
  }
}

/// Reserves the vertical space of [lines] text lines whether or not [child]
/// has anything to draw.
///
/// Poster rails size their cover with an [Expanded], so a card whose caption
/// happens to be one line shorter than its neighbour's silently gets a TALLER
/// poster — the row ends up ragged. Reserving the caption box keeps every
/// poster in a rail identical, and scales with the user's text size.
class FixedTextLines extends StatelessWidget {
  const FixedTextLines({
    super.key,
    required this.fontSize,
    required this.lineHeight,
    this.lines = 1,
    this.child,
  });

  final double fontSize;
  final double lineHeight;
  final int lines;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(fontSize);
    return SizedBox(height: scaled * lineHeight * lines, child: child);
  }
}

class HomeSkeletonBox extends StatelessWidget {
  const HomeSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(width: width, height: height, color: Colors.white),
    );
  }
}

/// Press feedback for a section header strip on Home.
///
/// Every rail's header is the tap target for its "View all" — a deliberate
/// earlier fix, since the old `TextButton` was a ~26dp target squeezed into the
/// row. But the strip was a bare [InkWell], and a bare InkWell across a
/// full-width header is the wrong feedback twice over: the splash is an
/// edge-to-edge rectangle with no radius, which reads as a rendering artifact
/// rather than as a button, and Material's default splash on a near-black
/// surface is so faint that on most taps nothing visible happens at all.
///
/// So the ink is switched off and the row answers instead — it dips and settles
/// back, the same press language the cards below it already use. The InkWell
/// itself stays, because it is what carries focus, hover and semantics; only
/// its painting is replaced.
class HomeSectionTapTarget extends StatefulWidget {
  const HomeSectionTapTarget({super.key, required this.child, this.onTap});

  final Widget child;

  /// Null disables the press effect along with the tap, so a header with
  /// nothing to open does not pretend otherwise.
  final VoidCallback? onTap;

  @override
  State<HomeSectionTapTarget> createState() => _HomeSectionTapTargetState();
}

class _HomeSectionTapTargetState extends State<HomeSectionTapTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return InkWell(
      onTap: widget.onTap,
      // Transparent, not absent: keeping the InkWell keeps focus traversal —
      // which the TV build depends on — and the semantics that make the strip
      // announce as a button.
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.white.withValues(alpha: 0.025),
      onHighlightChanged: enabled
          ? (value) {
              if (value != _pressed) setState(() => _pressed = value);
            }
          : null,
      child: AnimatedScale(
        // Barely there on purpose: a header is a large surface, and a scale big
        // enough to notice on a button looks like the layout jumped here.
        scale: _pressed && enabled ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed && enabled ? 0.6 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
