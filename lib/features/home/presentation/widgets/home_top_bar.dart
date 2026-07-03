import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_badge.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key, required this.blurProgress});

  final double blurProgress;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final progress = blurProgress.clamp(0.0, 1.0);

    final bar = Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 10, 12, 10),
      child: Row(
        children: [
          const Text(
            'SOZO',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
              height: 1,
            ),
          ),
          const SizedBox(width: 10),
          // Quick-switch between the user's favorite providers; the Flexible
          // absorbs the slack the old Spacer did so the icons stay right-aligned.
          const Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ProviderSwitcher(),
            ),
          ),
          const SizedBox(width: 8),
          const StreakBadge(),
          _TopBarIcon(
            icon: Icons.search_rounded,
            onTap: () => getIt<NavController>().goTo(1),
          ),
          _DownloadIndicator(),
          const _NotificationsIndicator(),
        ],
      ),
    );

    // No scroll — gradient scrim over banner
    if (progress < 0.01) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.80),
              Colors.transparent,
            ],
          ),
        ),
        child: bar,
      );
    }

    // Scrolling — frosted glass blur
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 14 * progress,
            sigmaY: 14 * progress,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.navBackground.withValues(alpha: 0.72 * progress),
              border: progress > 0.05
                  ? Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.07 * progress),
                        width: 0.5,
                      ),
                    )
                  : null,
            ),
            child: bar,
          ),
        ),
      ),
    );
  }
}

/// Compact pill in the top bar showing the current provider. Tapping it opens a
/// quick-switch sheet of the user's favorite providers (plus an "All providers"
/// shortcut to the full picker). With no favorites it jumps straight to the
/// full picker.
class _ProviderSwitcher extends StatelessWidget {
  const _ProviderSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
      builder: (context, state) {
        if (state is! ProviderLoaded) return const SizedBox.shrink();
        final current = state.currentProvider;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openSwitcher(context, state),
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 4, 7, 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProviderLogo(image: current?.image ?? '', size: 22),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      current?.name ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textHint,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<ProviderEntity> _resolveFavorites(ProviderLoaded state) {
    final favIds = getIt<HiveService>().getFavoriteProviders();
    final byId = {for (final p in state.providers) p.id: p};
    return [
      for (final id in favIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<void> _openSwitcher(BuildContext context, ProviderLoaded state) async {
    final bloc = context.read<ProviderBloc>();
    final favorites = _resolveFavorites(state);
    if (favorites.isEmpty) {
      openProviderPicker(context, bloc);
      return;
    }
    final result = await showAdaptiveModal<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProviderQuickSwitchSheet(
        favorites: favorites,
        currentProviderId: state.currentProviderId,
      ),
    );
    if (result == null || !context.mounted) return;
    if (result == _kAllProvidersAction) {
      openProviderPicker(context, bloc);
    } else {
      bloc.add(ProviderSelect(result));
    }
  }
}

/// Sentinel returned by the quick-switch sheet for the "All providers" row.
const String _kAllProvidersAction = '__all_providers__';

/// Bottom sheet listing the user's favorite providers for one-tap switching,
/// plus a shortcut to the full provider picker. Pops the chosen provider id
/// (or [_kAllProvidersAction]) so the caller owns navigation/selection.
class _ProviderQuickSwitchSheet extends StatelessWidget {
  const _ProviderQuickSwitchSheet({
    required this.favorites,
    required this.currentProviderId,
  });

  final List<ProviderEntity> favorites;
  final String currentProviderId;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Text(
                  'profile.favorites'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: favorites.length,
              itemBuilder: (context, i) {
                final p = favorites[i];
                final selected = p.id == currentProviderId;
                return ListTile(
                  leading: _ProviderLogo(image: p.image, size: 36),
                  title: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.primary, size: 20)
                      : null,
                  onTap: () => Navigator.of(context).pop(p.id),
                );
              },
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.apps_rounded,
                  color: AppColors.textSecondary, size: 18),
            ),
            title: Text(
              'profile.all_providers'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
            onTap: () => Navigator.of(context).pop(_kAllProvidersAction),
          ),
          SizedBox(height: bottomPad + 8),
        ],
      ),
    );
  }
}

/// Small rounded provider logo with a graceful fallback when the image is
/// missing or fails to load.
class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.image, required this.size});

  final String image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_filter_outlined,
        color: AppColors.textHint,
        size: size * 0.55,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: image.isEmpty
          ? fallback
          : Image.network(
              image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _NotificationsIndicator extends StatefulWidget {
  const _NotificationsIndicator();

  @override
  State<_NotificationsIndicator> createState() =>
      _NotificationsIndicatorState();
}

class _NotificationsIndicatorState extends State<_NotificationsIndicator>
    with WidgetsBindingObserver {
  final NotificationsRepository _repo = getIt<NotificationsRepository>();
  final HiveService _hive = getIt<HiveService>();
  Timer? _timer;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!_hive.isLoggedIn) {
      if (_count != 0 && mounted) setState(() => _count = 0);
      return;
    }
    final result = await _repo.unreadCount();
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        if (value != _count) setState(() => _count = value);
      case Failure():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          if (!_hive.isLoggedIn) {
            await context.push('/login');
            _refresh();
            return;
          }
          await context.push('/notifications');
          _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                if (_count > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: AppColors.navBackground,
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _count > 99 ? '99+' : '$_count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _DownloadIndicator extends StatefulWidget {
  @override
  State<_DownloadIndicator> createState() => _DownloadIndicatorState();
}

class _DownloadIndicatorState extends State<_DownloadIndicator>
    with SingleTickerProviderStateMixin {
  final DownloadService _service = getIt<DownloadService>();
  late final AnimationController _pulse;
  bool _hasActive = false;
  int _activeCount = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _service.revision.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_check);
    _pulse.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final items = _service.getAll();
    final active = items.where((i) => i.status == DownloadStatus.downloading).length;
    final hasActive = active > 0;
    if (hasActive != _hasActive || active != _activeCount) {
      setState(() {
        _hasActive = hasActive;
        _activeCount = active;
      });
      if (hasActive) {
        _pulse.repeat();
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasActive) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/downloads'),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) => Icon(
                    Icons.download_rounded,
                    color: Color.lerp(
                      AppColors.primary,
                      Colors.white,
                      (_pulse.value * 2 - 1).abs(),
                    ),
                    size: 24,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$_activeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
