import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:soplay/core/deeplink/deeplink_opt_in.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/nav_prefs.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_updater/presentation/services/update_checker.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../../core/navigation/app_tab.dart';
import '../../../../core/navigation/nav_controller.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  final GlobalKey _shortsRefreshShowcaseKey = GlobalKey();
  int _index = 0;
  int _shortsRefreshTick = 0;
  List<TabId> _visibleTabs = const [];
  late final NavController _navController;
  late final HiveService _hiveService;
  String? _lastProviderId;
  bool _shortsShowcaseStarted = false;

  int get _shortsIndex => _visibleTabs.indexOf(TabId.shorts); // -1 if hidden
  int get _homeIndex {
    final i = _visibleTabs.indexOf(TabId.home);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _navController = getIt<NavController>();
    _hiveService = getIt<HiveService>();
    // Reflect the persisted nav-style preference into the shared notifier the
    // nav listens to (so it renders correctly on first frame).
    NavPrefs.navStyle.value = _hiveService.navStyle;
    _visibleTabs = sanitizeTabOrder(_hiveService.tabOrder);
    NavPrefs.tabOrder.value = _hiveService.tabOrder;
    NavPrefs.tabOrder.addListener(_onTabSetChange);
    _navController.tabIndexResolver = (id) => _visibleTabs.indexOf(id);
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

  // The user changed the tab set in Settings → Appearance. Keep the SAME tab
  // selected if it survived; otherwise fall back to Home.
  void _onTabSetChange() {
    final currentId = (_index >= 0 && _index < _visibleTabs.length)
        ? _visibleTabs[_index]
        : TabId.home;
    final next = sanitizeTabOrder(NavPrefs.tabOrder.value);
    setState(() {
      _visibleTabs = next;
      final keep = next.indexOf(currentId);
      _index = keep >= 0 ? keep : _homeIndex;
    });
    _navController.goTo(_index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navController.index.removeListener(_onNavChange);
    NavPrefs.tabOrder.removeListener(_onTabSetChange);
    ShowcaseView.get().unregister();
    super.dispose();
  }

  void _onProviderStateChange(BuildContext context, ProviderState state) {
    if (state is! ProviderLoaded) return;
    final newId = state.currentProviderId;
    if (_lastProviderId == null) {
      _lastProviderId = newId;
      // HomePage.initState already fires a (non-silent) HomeLoad the moment the
      // shell mounts. Kicking a second one here while that is still in flight
      // runs BOTH handlers concurrently (bloc's default transformer), and the
      // late completion re-emits HomeLoaded/HomeError — churning HomeContent
      // through extra mounts. Only load if nothing is in flight or landed.
      final homeState = context.read<HomeBloc>().state;
      if (homeState is! HomeLoaded && homeState is! HomeLoading) {
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
    if (reselected && _shortsIndex >= 0 && index == _shortsIndex) {
      _refreshShorts();
    }
  }

  void _refreshShorts() {
    if (_shortsIndex < 0 || _index != _shortsIndex) return;
    setState(() => _shortsRefreshTick++);
  }

  void _maybeShowShortsRefreshTip() {
    if (_shortsIndex < 0 ||
        _index != _shortsIndex ||
        _shortsShowcaseStarted ||
        _hiveService.hasSeenShortsRefreshShowcase) {
      return;
    }
    _shortsShowcaseStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        if (_shortsIndex < 0 || _index != _shortsIndex) {
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
    final defs = [for (final id in _visibleTabs) kTabRegistry[id]!];
    final tabs = <Widget>[
      for (var i = 0; i < defs.length; i++)
        KeyedSubtree(
          // Stable per-tab key so reordering the bar MOVES a page (keeping its
          // State) instead of rebuilding it at a new index — which was
          // re-mounting Home and re-firing its "Join Telegram" sheet.
          key: ValueKey(defs[i].id),
          child: defs[i].builder(TabBuildContext(
            isActive: _index == i,
            shortsRefreshTick: _shortsRefreshTick,
          )),
        ),
    ];

    // Hide the floating bottom nav while a keyboard is open (e.g. searching),
    // otherwise it rides up and floats over the keyboard.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: BlocListener<ProviderBloc, ProviderState>(
        listener: _onProviderStateChange,
        child: PopScope(
          canPop: _index == _homeIndex,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            setState(() => _index = _homeIndex);
            _navController.goTo(_homeIndex);
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
                            items: defs,
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
                      // The tab body is OUTSIDE the nav-style listener so switching
                      // the nav style never re-mounts the tabs (that remount was
                      // re-triggering the Home "Join Telegram" sheet).
                      Positioned.fill(
                        child: IndexedStack(index: _index, children: tabs),
                      ),
                      if (!keyboardOpen)
                        Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ValueListenableBuilder<String>(
                          valueListenable: NavPrefs.navStyle,
                          builder: (context, style, _) {
                            // Classic: the original full-width frosted bar (keeps
                            // the per-tab Showcase + real double-tap-to-refresh).
                            if (style == NavPrefs.classic) {
                              return _SoplayClassicBar(
                                index: _index,
                                items: defs,
                                shortsShowcaseKey: _shortsRefreshShowcaseKey,
                                onTap: _onTabTap,
                                onShortsDoubleTap: _refreshShorts,
                              );
                            }
                            // Glass / Solid: a floating capsule inset 16 each side.
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                MediaQuery.paddingOf(context).bottom + 12,
                              ),
                              child: _SoplayGlassCapsule(
                                index: _index,
                                items: defs,
                                glass: style == NavPrefs.glass,
                                shortsShowcaseKey: _shortsRefreshShowcaseKey,
                                onTabSelected: _handleTabTap,
                              ),
                            );
                          },
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
    required this.items,
    required this.glass,
    required this.shortsShowcaseKey,
    required this.onTabSelected,
  });

  final int index;
  final List<AppTabDef> items;

  /// When false, render a shader-free solid dark capsule (lighter for weak
  /// devices / users who turned liquid glass off in Profile → Appearance).
  final bool glass;

  final GlobalKey shortsShowcaseKey;
  final ValueChanged<int> onTabSelected;

  static const double _barHeight = 62;

  // Refractive dark glass — matches the app's dark surfaces (dark backer pad),
  // but with a brighter specular rim, thicker body and a touch of chromatic
  // edge so it reads as a real, pretty piece of glass (not a flat frost).
  static const _glassSettings = LiquidGlassSettings(
    thickness: 20,
    blur: 5, // less haze behind the bar → cleaner, not muddy
    chromaticAberration: 0.18, // subtle edge tint, not a rainbow smear
    refractiveIndex: 1.5,
    saturation: 1.08,
    lightIntensity: 1.25, // crisp top-edge specular highlight
    ambientStrength: 1,
    glowIntensity: 0.7, // gentle luminous rim
    glassColor: Color(0x12FFFFFF), // faint white sheen
    backerColor: Color(0xE61A1A1A), // near-solid dark pad → premium, not hazy
    whitenStrength: 0.0,
  );

  // Solid (glass off): a near-opaque dark pad, no blur/refraction — the cheap,
  // always-smooth path.
  static const _solidSettings = LiquidGlassSettings(
    thickness: 0,
    blur: 0,
    chromaticAberration: 0,
    refractiveIndex: 1,
    saturation: 1,
    lightIntensity: 0,
    ambientStrength: 0,
    glassColor: Color(0x00000000),
    backerColor: Color(0xF01A1A1A), // ~94% solid dark
    whitenStrength: 0.0,
  );

  @override
  Widget build(BuildContext context) {
    final bar = GlassTabBar.bottom(
      tabs: [
        for (final it in items)
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
      magnification: glass ? 1.12 : 1.0, // subtle iOS-26 lens on the selected tab
      indicatorPinchStrength: glass ? 0.3 : 0.0,
      // Selected-tab pill: a soft, restrained light pill on the dark body.
      indicatorColor: Color(glass ? 0x22FFFFFF : 0x18FFFFFF),
      quality: glass ? null : GlassQuality.minimal,
      settings: glass ? _glassSettings : _solidSettings,
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

/// Classic full-width frosted bottom bar — the ORIGINAL mobile nav, offered as a
/// style option (Profile → Appearance). Unlike the glass capsule it keeps the
/// per-tab Showcase anchor and double-tap-to-refresh, since each tab is its own
/// [_ClassicNavButton].
class _SoplayClassicBar extends StatelessWidget {
  const _SoplayClassicBar({
    required this.index,
    required this.items,
    required this.shortsShowcaseKey,
    required this.onTap,
    required this.onShortsDoubleTap,
  });

  final int index;
  final List<AppTabDef> items;
  final GlobalKey shortsShowcaseKey;
  final ValueChanged<int> onTap;
  final VoidCallback onShortsDoubleTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 68 + bottomPad,
          decoration: BoxDecoration(
            // A translucent frosted grey (not near-black) so content shows
            // through the blur and the bar reads as frosted glass.
            color: const Color(0xFF262626).withValues(alpha: 0.72),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: bottomPad == 0 ? 8 : bottomPad,
            ),
            child: Row(
              children: List.generate(
                items.length,
                (i) => Expanded(
                  child: _ClassicNavButton(
                    item: items[i],
                    selected: index == i,
                    showcaseKey: items[i].id == TabId.shorts
                        ? shortsShowcaseKey
                        : null,
                    onTap: () => onTap(i),
                    onDoubleTap: items[i].id == TabId.shorts
                        ? onShortsDoubleTap
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassicNavButton extends StatefulWidget {
  const _ClassicNavButton({
    required this.item,
    required this.selected,
    required this.showcaseKey,
    required this.onTap,
    required this.onDoubleTap,
  });

  final AppTabDef item;
  final bool selected;
  final GlobalKey? showcaseKey;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_ClassicNavButton> createState() => _ClassicNavButtonState();
}

class _ClassicNavButtonState extends State<_ClassicNavButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? Colors.white : const Color(0xFF7A7A7A);

    final button = Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.labelKey.tr(),
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        onDoubleTap: widget.selected ? widget.onDoubleTap : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: _pressed ? 0.92 : 1,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _pressed ? 0.68 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  scale: widget.selected ? 1.1 : 1,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      widget.selected
                          ? widget.item.activeIcon
                          : widget.item.icon,
                      key: ValueKey('${widget.item.labelKey}-${widget.selected}'),
                      size: 24,
                      color: color,
                      shadows: widget.selected
                          ? [
                              Shadow(
                                color: Colors.white.withValues(alpha: 0.28),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight:
                        widget.selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                  child: Text(
                    widget.item.labelKey.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final key = widget.showcaseKey;
    if (key == null) return button;

    return Showcase.withWidget(
      key: key,
      tooltipPosition: TooltipPosition.top,
      targetBorderRadius: BorderRadius.circular(18),
      targetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      targetTooltipGap: 14,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      blurValue: 1.5,
      container: const _ShortsRefreshShowcaseCard(),
      child: button,
    );
  }
}

/// Sozo-Desktop style floating bottom-center rounded pill navigation.
/// Desktop only — mobile uses [_SoplayGlassCapsule]. Reuses the same 5 tabs.
class _SoplayFloatingNav extends StatelessWidget {
  const _SoplayFloatingNav(
      {required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<AppTabDef> items;

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
          for (int i = 0; i < items.length; i++)
            _NavCircle(
              item: items[i],
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

  final AppTabDef item;
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
