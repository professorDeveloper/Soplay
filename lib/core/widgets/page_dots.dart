import 'package:flutter/material.dart';
import 'package:riasdxd/core/theme/app_colors.dart';

/// Canonical page indicator, standardised on the desktop hero carousel's dots.
/// Renders nothing for a single page.
class PageDots extends StatelessWidget {
  const PageDots({
    super.key,
    required this.count,
    required this.index,
    this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        final dot = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: active ? 22 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.textPrimary : AppColors.textHint,
            borderRadius: BorderRadius.circular(99),
          ),
        );
        if (onTap == null) return dot;
        return GestureDetector(onTap: () => onTap!(i), child: dot);
      }),
    );
  }
}
