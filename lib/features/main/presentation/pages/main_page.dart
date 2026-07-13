import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:soplay/core/deeplink/deeplink_opt_in.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_updater/presentation/services/update_checker.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/home/presentation/pages/home_page.dart';
import 'package:soplay/features/my_list/presentation/pages/my_list_page.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:soplay/features/search/presentation/pages/search_page.dart';
import 'package:soplay/features/shorts/presentation/pages/shorts_page.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../../core/navigation/nav_controller.dart';
import '../../../profile/presentation/pages/profile_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  static const int _shortsIndex = 2;

  final GlobalKey _shortsRefreshShowcaseKey = GlobalKey();
  int _index = 0;
  int _shortsRefreshTick = 0;
  late final NavController _navController;
  late final HiveService _hiveService;
  String? _lastProviderId;
  bool _shortsShowcaseStarted = false;

  @override
  void initState() {
    super.initState();
    _navController = getIt<NavController>();
    _hiveService = getIt<HiveService>();
    _navController.index.addListener(_onNavChange);
    WidgetsBinding.instance.addObserver(this);
    ShowcaseView.register(
      blurValue: 1.5,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      onFinish: _markShortsShowcaseSeen,
      onDismiss: (_) => _markShortsShowcaseSeen(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isDesktopPlatform) {
        getIt<UpdateChecker>().run(context);
        DeeplinkOptIn.maybePrompt(context);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted && !isDesktopPlatform) {
      getIt<UpdateChecker>().run(context);
    }
  }

  void _onNavChange() {
    setState(() => _index = _navController.index.value);
    _maybeShowShortsRefreshTip();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navController.index.removeListener(_onNavChange);
    ShowcaseView.get().unregister();
    super.dispose();
  }

  void _onProviderStateChange(BuildContext context, ProviderState state) {
    if (state is! ProviderLoaded) return;
    final newId = state.currentProviderId;
    if (_lastProviderId == null) {
      _lastProviderId = newId;
      if (context.read<HomeBloc>().state is! HomeLoaded) {
        context.read<HomeBloc>().add(HomeLoad(silent: true));
      }
      return;
    }
    if (_lastProviderId == newId) return;
    _lastProviderId = newId;
    context.read<HomeBloc>().add(HomeLoad(silent: true));
    context.read<SearchBloc>().add(const SearchLoad());
  }

  void _onTabTap(int index) {
    setState(() => _index = index);
    _navController.goTo(index);
    _maybeShowShortsRefreshTip();
  }

  // The glass capsule has no per-tab double-tap, so re-tapping the already-active
  // Shorts tab refreshes the reel (the packaged bar fires onTabSelected on active
  // re-taps). Capture the "was already selected" state before _onTabTap mutates
  // _index.
  void _handleTabTap(int index) {
    final reselected = index == _index;
    _onTabTap(index);
    if (reselected && index == _shortsIndex) _refreshShorts();
  }

  void _refreshShorts() {
    if (_index != _shortsIndex) return;
    setState(() => _shortsRefreshTick++);
  }

  void _maybeShowShortsRefreshTip() {
    if (_index != _shortsIndex ||
        _shortsShowcaseStarted ||
        _hiveService.hasSeenShortsRefreshShowcase) {
      return;
    }
    _shortsShowcaseStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        if (_index != _shortsIndex) {
          _shortsShowcaseStarted = false;
          return;
        }
        ShowcaseView.get().startShowCase([_shortsRefreshShowcaseKey]);
      });
    });
  }

  void _markShortsShowcaseSeen() {
    if (_hiveService.hasSeenShortsRefreshShowcase) return;
    unawaited(_hiveService.markShortsRefreshShowcaseSeen());
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const HomePage(),
      const SearchPage(),
      ShortsPage(
        active: _index == _shortsIndex,
        refreshTick: _shortsRefreshTick,
      ),
      const MyListPage(),
      const ProfilePage(),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: BlocListener<ProviderBloc, ProviderState>(
        listener: _onProviderStateChange,
        child: PopScope(
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            setState(() => _index = 0);
            _navController.goTo(0);
          },
          child: isDesktopPlatform
              ? Scaffold(
                  backgroundColor: AppColors.background,
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(index: _index, children: tabs),
                      ),
                      // Sozo-Desktop: floating bottom-center rounded pill nav
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _SoplayFloatingNav(
                            index: _index,
                            onTap: _onTabTap,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Scaffold(
                  backgroundColor: AppColors.background,
                  extendBody: true,
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(index: _index, children: tabs),
                      ),
                      // iOS-26 floating liquid-glass capsule, inset 16 each side
                      // and raised above the safe area. Content scrolls behind it
                      // (extendBody) so it refracts/blurs the page.
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: MediaQuery.paddingOf(context).bottom + 12,
                        child: _SoplayGlassCapsule(
                          index: _index,
                          shortsShowcaseKey: _shortsRefreshShowcaseKey,
                          onTabSelected: _handleTabTap,
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

/// iOS-26 "Liquid Glass" FLOATING capsule — the MOBILE bottom nav.
///
/// Built on liquid_glass_widgets' [GlassTabBar.bottom]. Mounted only from the
/// mobile Scaffold branch as a bottom-center overlay with `extendBody: true`, so
/// the content scrolling behind it is refracted/blurred (native iOS-26 look).
/// Desktop keeps [_SoplayFloatingNav]; this is never mounted on desktop, and the
/// glass shaders are pre-warmed / wrapped mobile-only in main.dart.
///
/// The packaged bar exposes no per-tab GlobalKey or double-tap, so: the Shorts
/// refresh Showcase highlights the whole capsule (Shorts is the central tab),
/// and double-tap-to-refresh becomes re-tapping the already-active Shorts tab
/// (see [_MainPageState._handleTabTap]).
class _SoplayGlassCapsule extends StatelessWidget {
  const _SoplayGlassCapsule({
    required this.index,
    required this.shortsShowcaseKey,
    required this.onTabSelected,
  });

  final int index;
  final GlobalKey shortsShowcaseKey;
  final ValueChanged<int> onTabSelected;

  static const double _barHeight = 62;

  // The 5 tabs (order: Home, Search, Shorts, MyList, Profile). Also reused by
  // the desktop _SoplayFloatingNav / _NavCircle.
  static const _items = [
    _NavItem(
      icon: CupertinoIcons.house,
      activeIcon: CupertinoIcons.house_fill,
      labelKey: 'navigation.home',
    ),
    _NavItem(
      icon: CupertinoIcons.search,
      activeIcon: CupertinoIcons.search,
      labelKey: 'navigation.search',
    ),
    _NavItem(
      icon: CupertinoIcons.play_rectangle,
      activeIcon: CupertinoIcons.play_rectangle_fill,
      labelKey: 'navigation.shorts',
    ),
    _NavItem(
      icon: CupertinoIcons.bookmark,
      activeIcon: CupertinoIcons.bookmark_fill,
      labelKey: 'navigation.my_list',
    ),
    _NavItem(
      icon: CupertinoIcons.person,
      activeIcon: CupertinoIcons.person_fill,
      labelKey: 'navigation.profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bar = GlassTabBar.bottom(
      tabs: [
        for (final it in _items)
          GlassTab(
            label: it.labelKey.tr(),
            icon: Icon(it.icon),
            activeIcon: Icon(it.activeIcon),
          ),
      ],
      selectedIndex: index,
      onTabSelected: onTabSelected,
      // Outer Positioned(left:16,right:16) owns the float inset; the bar expands
      // to fill it (tabWidth null) and its own padding is zeroed.
      tabWidth: null,
      horizontalPadding: 0,
      verticalPadding: 0,
      barHeight: _barHeight,
      barBorderRadius: _barHeight / 2, // full capsule
      magnification: 1.15, // iOS-26 lens on the selected tab
      indicatorPinchStrength: 0.4,
      // Dark-readable moving indicator pill (default white ~10% is too faint).
      indicatorColor: const Color(0x2EFFFFFF),
      // Dark-readable bar glass: a bright tint (glassColor alpha IS the tint
      // strength) + ungated frost so it reads clearly over the dark UI.
      settings: const LiquidGlassSettings(
        thickness: 24,
        blur: 6,
        chromaticAberration: 0.3,
        refractiveIndex: 1.5,
        saturation: 1.3,
        lightIntensity: 0.8,
        ambientStrength: 1,
        glassColor: Color(0x40FFFFFF), // white ~25% base tint
        whitenStrength: 0.12,
        whitenGated: false, // even frost over dark content
      ),
      selectedIconColor: Colors.white,
      unselectedIconColor: const Color(0xFF7A7A7A),
      selectedLabelColor: Colors.white,
      unselectedLabelColor: const Color(0xFF7A7A7A),
      labelFontSize: 10.5,
    );

    // The package drop shadow is light-mode only, so paint our own soft capsule
    // shadow behind the glass for the "floating" look on the dark UI.
    final shadowed = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_barHeight / 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    spreadRadius: -4,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
        ),
        bar,
      ],
    );

    // No per-tab key on the packaged bar → the Showcase spotlights the whole
    // capsule (Shorts is the visually central tab). Register/start/seen flow is
    // unchanged.
    return Showcase.withWidget(
      key: shortsShowcaseKey,
      tooltipPosition: TooltipPosition.top,
      targetBorderRadius: BorderRadius.circular(_barHeight / 2),
      targetPadding: const EdgeInsets.all(6),
      targetTooltipGap: 14,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      blurValue: 1.5,
      container: const _ShortsRefreshShowcaseCard(),
      child: shadowed,
    );
  }
}

/// Sozo-Desktop style floating bottom-center rounded pill navigation.
/// Desktop only — mobile uses [_SoplayGlassCapsule]. Reuses the same 5 tabs.
class _SoplayFloatingNav extends StatelessWidget {
  const _SoplayFloatingNav({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        borderRadius: BorderRadius.circular(9999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 55,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.17),
            blurRadius: 13,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < _SoplayGlassCapsule._items.length; i++)
            _NavCircle(
              item: _SoplayGlassCapsule._items[i],
              selected: index == i,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _NavCircle extends StatefulWidget {
  const _NavCircle({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavCircle> createState() => _NavCircleState();
}

class _NavCircleState extends State<_NavCircle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final color = active
        ? AppColors.primary
        : (_hover ? AppColors.textPrimary : AppColors.textSecondary);

    return Tooltip(
      message: widget.item.labelKey.tr(),
      preferBelow: false,
      verticalOffset: 34,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.2 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Container(
              width: 50,
              height: 50,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
              ),
              child: Icon(
                active ? widget.item.activeIcon : widget.item.icon,
                color: color,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.labelKey,
  });

  final IconData icon;
  final IconData activeIcon;
  final String labelKey;
}

class _ShortsRefreshShowcaseCard extends StatelessWidget {
  const _ShortsRefreshShowcaseCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 276,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.06),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE53935).withValues(alpha: 0.35),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'main.shorts_refresh_title'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'main.shorts_refresh_body'.tr(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'main.tap_again'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ShowcaseView.get().dismiss(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'general.ok'.tr(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
