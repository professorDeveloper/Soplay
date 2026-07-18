import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// The 1…N clip progress indicator shown at the top of the game. Answered clips
/// read as solid dots, the clip in play is a stretched brand-red pill, and
/// upcoming clips are faint. Sizes are fixed so a 10-clip round fits one row.
class ProgressDots extends StatelessWidget {
  const ProgressDots({
    super.key,
    required this.total,
    required this.currentIndex,
  });

  final int total;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isCurrent = i == currentIndex;
        final isDone = i < currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: isCurrent ? 22 : 8,
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.primary
                : isDone
                    ? AppColors.textPrimary
                    : AppColors.textHint,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
