import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';

class ShimmerWrapper extends StatelessWidget {
  const ShimmerWrapper({super.key, required this.child});
  final Widget child;

  // Subtle sweep tuned for the dark surface — low contrast, slow period.
  static const _base = Color(0xFF202020);
  static const _highlight = Color(0xFF2B2B2B);

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
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/124.0 Mobile Safari/537.36',
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
      child: Center(child: Icon(icon, color: AppColors.textHint, size: 28)),
    );
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
