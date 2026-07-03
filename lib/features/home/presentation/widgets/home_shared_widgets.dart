import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';

class ShimmerWrapper extends StatelessWidget {
  const ShimmerWrapper({super.key, required this.child});
  final Widget child;

  static const _base = Color(0xFF1E1E1E);
  static const _highlight = Color(0xFF383838);

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: _base,
    highlightColor: _highlight,
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

  /// Optional explicit image request headers (e.g. provider Referer/UA). When
  /// null, a same-origin Referer + browser UA is derived from the image URL.
  final Map<String, String>? headers;

  /// Many provider CDNs (CloudStream/aniyomi/manga sources) hotlink-protect
  /// posters with a `Referer` check and/or reject non-browser User-Agents, so a
  /// bare `Image.network` 403s and shows a broken placeholder. A same-origin
  /// Referer + a browser UA satisfies the common cases.
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
          // Decode at the on-screen width (× DPR) instead of the source's full
          // resolution. Posters/banners are small on screen, so this slashes the
          // decoded-bitmap memory that was OOM-killing the app on heavy home
          // pages — with no visible quality change.
          final dpr = MediaQuery.devicePixelRatioOf(context);
          // The cacheWidth cap is a mobile OOM guard. Desktop has ample RAM, so
          // decode at full source resolution there for crisp posters.
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
