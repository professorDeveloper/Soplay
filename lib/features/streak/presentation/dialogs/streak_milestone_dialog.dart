import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Celebration shown when the user crosses a milestone (7 / 30 / 100 / 365…).
/// Lightweight on purpose — a CustomPaint confetti burst, gradient flame, and
/// two CTAs. Dismiss returns control to the player.
class StreakMilestoneDialog extends StatefulWidget {
  const StreakMilestoneDialog({super.key, required this.days});

  final int days;

  static Future<void> show(BuildContext context, int days) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Streak milestone',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => StreakMilestoneDialog(days: days),
      transitionBuilder: (_, anim, _, child) {
        final scale = Curves.easeOutBack.transform(anim.value.clamp(0, 1));
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(scale: 0.85 + 0.15 * scale, child: child),
        );
      },
    );
  }

  @override
  State<StreakMilestoneDialog> createState() => _StreakMilestoneDialogState();
}

class _StreakMilestoneDialogState extends State<StreakMilestoneDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiCtl;

  @override
  void initState() {
    super.initState();
    _confettiCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
  }

  @override
  void dispose() {
    _confettiCtl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = 'streak.share_text'.tr(args: ['${widget.days}']);
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _confettiCtl,
                    builder: (_, _) => CustomPaint(
                      painter: _ConfettiPainter(_confettiCtl.value),
                    ),
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A1015), Color(0xFF160A0C)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFE50914).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.3),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Flame(),
                    const SizedBox(height: 18),
                    Text(
                      'streak.milestone_title'
                          .tr(args: ['${widget.days}']),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'streak.milestone_subtitle'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              foregroundColor: AppColors.textPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'streak.cta_continue'.tr(),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _share,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.ios_share_rounded, size: 16),
                            label: Text(
                              'streak.cta_share'.tr(),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Flame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFC089), Color(0xFFE50914)],
          stops: [0, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE50914).withValues(alpha: 0.5),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(
        Icons.local_fire_department_rounded,
        color: Colors.white,
        size: 50,
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress);
  final double progress;

  static const _seedCount = 36;
  static const _palette = <Color>[
    Color(0xFFE50914),
    Color(0xFFFFB97A),
    Color(0xFFFFD86B),
    Color(0xFFFFFFFF),
    Color(0xFFFF6A2C),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (var i = 0; i < _seedCount; i++) {
      final angle = (i / _seedCount) * math.pi * 2 +
          rng.nextDouble() * 0.4;
      final dist = 40 + rng.nextDouble() * 180 * progress;
      final dx = cx + math.cos(angle) * dist;
      final dy = cy + math.sin(angle) * dist + progress * 60;
      final color = _palette[i % _palette.length].withValues(
        alpha: (1.0 - progress).clamp(0, 1),
      );
      final paint = Paint()..color = color;
      final w = 5.0 + rng.nextDouble() * 4;
      final h = 8.0 + rng.nextDouble() * 6;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(progress * math.pi * 2 + i.toDouble());
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
