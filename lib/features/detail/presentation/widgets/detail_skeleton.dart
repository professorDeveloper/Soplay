import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    // Same formula the real hero uses in detail_page.dart. A fixed 420 meant
    // the header visibly jumped by up to a hundred pixels the moment the page
    // swapped from skeleton to content.
    final heroHeight =
        (MediaQuery.sizeOf(context).height * 0.55).clamp(320.0, 440.0);
    return Shimmer.fromColors(
      baseColor: const Color(0xFF1E1E1E),
      highlightColor: const Color(0xFF383838),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkBox(width: double.infinity, height: heroHeight + topPad, radius: 0),
            const _Pad(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16),
                  Row(
                    children: [
                      _SkBox(width: 50, height: 14, radius: 4),
                      SizedBox(width: 12),
                      _SkBox(width: 60, height: 14, radius: 4),
                      SizedBox(width: 12),
                      _SkBox(width: 70, height: 14, radius: 4),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      _SkBox(width: 60, height: 22, radius: 6),
                      SizedBox(width: 8),
                      _SkBox(width: 80, height: 22, radius: 6),
                      SizedBox(width: 8),
                      _SkBox(width: 70, height: 22, radius: 6),
                    ],
                  ),
                  SizedBox(height: 18),
                  _SkBox(width: double.infinity, height: 13, radius: 4),
                  SizedBox(height: 6),
                  _SkBox(width: double.infinity, height: 13, radius: 4),
                  SizedBox(height: 6),
                  _SkBox(width: 200, height: 13, radius: 4),
                  SizedBox(height: 18),
                  _SkBox(width: double.infinity, height: 46, radius: 6),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _Pad(
              child: Row(
                children: [
                  _SkBox(width: 56, height: 14, radius: 4),
                  SizedBox(width: 22),
                  _SkBox(width: 44, height: 14, radius: 4),
                  SizedBox(width: 22),
                  _SkBox(width: 70, height: 14, radius: 4),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _PosterGridSk(),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _SkBox extends StatelessWidget {
  const _SkBox({required this.width, required this.height, this.radius = 8});
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

class _Pad extends StatelessWidget {
  const _Pad({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

/// Stands in for the first tab, which is the three-across poster grid.
class _PosterGridSk extends StatelessWidget {
  const _PosterGridSk();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col > 0) const SizedBox(width: 8),
                    const Expanded(
                      child: AspectRatio(
                        aspectRatio: 0.66,
                        child: _SkBox(
                          width: double.infinity,
                          height: double.infinity,
                          radius: 8,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
