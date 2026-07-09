import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/streak/data/streak_service.dart';

class StreakBadge extends StatefulWidget {
  const StreakBadge({super.key});

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final StreakService _service = getIt<StreakService>();
  final HiveService _hive = getIt<HiveService>();
  late final AnimationController _pulse;
  Timer? _refreshTimer;

  static const int _profileTabIndex = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _service.state.addListener(_onStateChanged);
    _onStateChanged();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_service.state.value.isAtRisk) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      if (_pulse.isAnimating) {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
    setState(() {});
  }

  void _refresh() {
    if (_hive.isLoggedIn) _service.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.state.removeListener(_onStateChanged);
    _refreshTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _service.state.value;
    if (!_hive.isLoggedIn) return const SizedBox.shrink();
    if (state.current <= 0) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => getIt<NavController>().goTo(_profileTabIndex),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) {
              final pulse = state.isAtRisk ? _pulse.value : 0.0;
              return _BadgeBody(
                count: state.current,
                pulse: pulse,
                freezes: state.freezes.available,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BadgeBody extends StatelessWidget {
  const _BadgeBody({
    required this.count,
    required this.pulse,
    this.freezes = 0,
  });

  final int count;
  final double pulse;
  final int freezes;

  @override
  Widget build(BuildContext context) {
    final glow = pulse * 6;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFC078), Color(0xFFEF7A35)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF7A35).withValues(alpha: 0.28 + pulse * 0.35),
            blurRadius: 10 + glow,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: 0.2,
            ),
          ),
          if (freezes > 0) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.ac_unit_rounded,
              color: Colors.white,
              size: 11,
            ),
          ],
        ],
      ),
    );
  }
}
