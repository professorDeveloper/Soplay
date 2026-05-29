import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

/// Streak block for the profile page. Combines a glowing flame, a 7-day grid
/// of the user's recent activity, and the personal-best record.
class StreakCard extends StatefulWidget {
  const StreakCard({super.key});

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> {
  final StreakService _service = getIt<StreakService>();
  final HiveService _hive = getIt<HiveService>();

  @override
  void initState() {
    super.initState();
    _service.state.addListener(_onChange);
    if (_hive.isLoggedIn) _service.refresh();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.state.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hive.isLoggedIn) return const SizedBox.shrink();
    final state = _service.state.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'streak.section_label'.tr(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _StreakCardBody(state: state),
        ],
      ),
    );
  }
}

class _StreakCardBody extends StatelessWidget {
  const _StreakCardBody({required this.state});
  final StreakState state;

  @override
  Widget build(BuildContext context) {
    final hasStreak = state.current > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: hasStreak
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2A1112),
                  Color(0xFF1B0F11),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1F1F22), Color(0xFF161618)],
              ),
        border: Border.all(
          color: hasStreak
              ? const Color(0xFFE50914).withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          width: 0.7,
        ),
        boxShadow: hasStreak
            ? [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _FlameMedallion(active: hasStreak),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasStreak
                            ? 'streak.current_n_days'.tr(args: ['${state.current}'])
                            : 'streak.empty_title'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasStreak
                            ? (state.pingedToday
                                ? 'streak.locked_today'.tr()
                                : (state.isAtRisk
                                    ? 'streak.risk_subtitle'.tr()
                                    : 'streak.keep_going'.tr()))
                            : 'streak.empty_subtitle'.tr(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _WeekStrip(state: state),
            const SizedBox(height: 14),
            Row(
              children: [
                _StatPill(
                  icon: Icons.emoji_events_rounded,
                  label: 'streak.record_label'.tr(),
                  value: '${state.longest}',
                ),
                const SizedBox(width: 10),
                _StatPill(
                  icon: Icons.bolt_rounded,
                  label: 'streak.next_milestone'.tr(),
                  value: '${_nextMilestone(state.current)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _nextMilestone(int current) {
    const list = [7, 30, 60, 100, 180, 365, 500, 1000];
    for (final m in list) {
      if (current < m) return m;
    }
    return list.last;
  }
}

class _FlameMedallion extends StatelessWidget {
  const _FlameMedallion({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active
            ? const RadialGradient(
                colors: [Color(0xFFFF8A3A), Color(0xFFE50914)],
                stops: [0, 1],
              )
            : RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.02),
                ],
                stops: const [0, 1],
              ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.local_fire_department_rounded,
        color: active ? Colors.white : Colors.white38,
        size: 30,
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.state});
  final StreakState state;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final cells = List.generate(7, (i) {
      final date = today.subtract(Duration(days: 6 - i));
      final isToday = i == 6;
      // We can't know the exact per-day history without a backend endpoint —
      // assume the trailing N days were active where N = min(current, 7).
      final activeCount = state.current.clamp(0, 7);
      final activeFrom = 7 - activeCount;
      final isActive = i >= activeFrom &&
          (!isToday || state.pingedToday || state.current > 0);
      return _DayCell(
        weekday: _shortDay(date.weekday),
        day: '${date.day}',
        active: isActive,
        isToday: isToday,
        pingedToday: state.pingedToday,
      );
    });
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          Expanded(child: cells[i]),
          if (i < cells.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  String _shortDay(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'streak.weekday_mon'.tr(),
      DateTime.tuesday => 'streak.weekday_tue'.tr(),
      DateTime.wednesday => 'streak.weekday_wed'.tr(),
      DateTime.thursday => 'streak.weekday_thu'.tr(),
      DateTime.friday => 'streak.weekday_fri'.tr(),
      DateTime.saturday => 'streak.weekday_sat'.tr(),
      _ => 'streak.weekday_sun'.tr(),
    };
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.weekday,
    required this.day,
    required this.active,
    required this.isToday,
    required this.pingedToday,
  });

  final String weekday;
  final String day;
  final bool active;
  final bool isToday;
  final bool pingedToday;

  @override
  Widget build(BuildContext context) {
    final highlight = isToday && pingedToday;
    final border = isToday && !pingedToday
        ? Border.all(
            color: const Color(0xFFFFB97A).withValues(alpha: 0.7),
            width: 1.2,
          )
        : null;
    return Column(
      children: [
        Text(
          weekday,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF7A37), Color(0xFFE50914)],
                    )
                  : LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.05),
                        Colors.white.withValues(alpha: 0.02),
                      ],
                    ),
              border: border,
            ),
            child: Center(
              child: active
                  ? const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : Text(
                      day,
                      style: TextStyle(
                        color: highlight
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFFB97A), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
