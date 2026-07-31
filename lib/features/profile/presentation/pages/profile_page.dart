import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/profile/presentation/widgets/tab_customizer_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/aniyomi/presentation/pages/aniyomi_sources_page.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/system/nav_prefs.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/manga/presentation/pages/manga_sources_page.dart';
import 'package:soplay/features/cloudstream/presentation/pages/cloudstream_sources_page.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/private_list/presentation/private_unlock.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_card.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => const _ProfileView();
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  final _scrollController = ScrollController();
  final _headerBlur = ValueNotifier<double>(0.0);

  static const double _headerContentHeight = 58.0;

  // Desktop settings use a Sozo-Desktop style sidebar + panel layout.
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    context.read<AuthBloc>().add(const AuthStarted());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _headerBlur.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = (_scrollController.offset / 80.0).clamp(0.0, 1.0);
    if ((next - _headerBlur.value).abs() > 0.01) {
      _headerBlur.value = next;
    }
  }

  Future<void> _onRefresh() async {
    context.read<AuthBloc>().add(const AuthProfileRefreshRequested());
    context.read<ProviderBloc>().add(const ProviderLoad());
    await Future.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) return _buildDesktop(context);

    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final headerH = topPad + _headerContentHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E1416), Color(0xFF181818), Color(0xFF101010)],
                stops: [0, 0.35, 1],
              ),
            ),
            child: SizedBox.expand(),
          ),
          _ProfileScrollFrame(
            child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            edgeOffset: headerH,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: headerH + 16)),
                SliverToBoxAdapter(
                  child: BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      final user =
                          state is AuthLoaded ? state.token.user : null;
                      return _Reveal(order: 0, child: _ProfileHeader(user: user));
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                const SliverToBoxAdapter(
                  child: _Reveal(order: 1, child: StreakCard()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(
                  child: _Reveal(order: 2, child: _ProvidersSection()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                if (BridgeControl.canHost && CloudStreamChannel.isSupported) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s',
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                  Icons.extension_outlined,
                                  color: AppColors.primary),
                            ),
                          ),
                          title: Text('profile.cloudstream_sources'.tr(),
                              style: const TextStyle(color: Colors.white)),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textHint),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CloudStreamSourcesPage(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
                if (BridgeControl.canHost && AniyomiChannel.isSupported) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                  Icons.play_circle_outline,
                                  color: AppColors.textHint),
                            ),
                          ),
                          title: Text('profile.aniyomi_sources'.tr(),
                              style: const TextStyle(color: Colors.white)),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textHint),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AniyomiSourcesPage(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
                if (BridgeControl.canHost && MangaChannel.isSupported) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                  Icons.menu_book_outlined,
                                  color: AppColors.textHint),
                            ),
                          ),
                          title: Text('manga.sources_title'.tr(),
                              style: const TextStyle(color: Colors.white)),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textHint),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MangaSourcesPage(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
                const SliverToBoxAdapter(
                  child: _Reveal(order: 3, child: _WatchHistorySection()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(
                  child: _Reveal(order: 4, child: _SecuritySection()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(
                  child: _Reveal(order: 5, child: _AppearanceEntry()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(
                  child: _Reveal(order: 6, child: _PlayerEntry()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(
                  child: _Reveal(order: 7, child: _AboutSection()),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: bottomPad + (isDesktopPlatform ? 112 : 96),
                  ),
                ),
              ],
            ),
          ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _headerBlur,
              builder: (_, blur, _) {
                final progress = blur.clamp(0.0, 1.0);
                final title = Text(
                  'profile.title'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                );
                final content = Container(
                  padding: EdgeInsets.fromLTRB(20, topPad + 14, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.navBackground
                        .withValues(alpha: 0.78 * progress),
                    border: progress > 0.05
                        ? Border(
                            bottom: BorderSide(
                              color: Colors.white
                                  .withValues(alpha: 0.07 * progress),
                              width: 0.5,
                            ),
                          )
                        : null,
                  ),
                  child: isDesktopPlatform
                      ? Center(
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 760),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: title,
                              ),
                            ),
                          ),
                        )
                      : title,
                );
                if (progress < 0.01) return content;
                return ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 20 * progress,
                      sigmaY: 20 * progress,
                    ),
                    child: content,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Desktop: Sozo-Desktop style sidebar + panel ───────────────────────────
  static const _desktopNav = <(IconData, String)>[
    (Icons.person_outline_rounded, 'Account'),
    (Icons.dns_outlined, 'Providers'),
    (Icons.history_rounded, 'Activity'),
    (Icons.lock_outline_rounded, 'Security'),
    (Icons.palette_outlined, 'Appearance'),
    (Icons.info_outline_rounded, 'About'),
  ];

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSidebar(
            items: _desktopNav,
            index: _navIndex,
            onTap: (i) => setState(() => _navIndex = i),
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0x14FFFFFF),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(36, 34, 36, 120),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_navIndex),
                      child: _desktopPanel(_navIndex),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopPanel(int index) {
    switch (index) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final user = state is AuthLoaded ? state.token.user : null;
                return _ProfileHeader(user: user);
              },
            ),
            const SizedBox(height: 8),
            const StreakCard(),
          ],
        );
      case 1:
        return const _ProvidersSection();
      case 2:
        return const _WatchHistorySection();
      case 3:
        return const _SecuritySection();
      case 4:
        return const _AppearanceSection();
      default:
        return const _AboutSection();
    }
  }
}

/// Sozo-Desktop style settings sidebar: fixed-width nav rail with a title and
/// hoverable, active-tinted category items.
class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      color: AppColors.navBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
            child: Text(
              'profile.title'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (int i = 0; i < items.length; i++)
            _SettingsNavItem(
              icon: items[i].$1,
              label: items[i].$2,
              active: index == i,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatefulWidget {
  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active
        ? AppColors.primary
        : (_hover ? AppColors.textPrimary : AppColors.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.12)
                : (_hover
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: color, size: 18),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered fade + slide-up entrance for each settings section (desktop only,
/// akuse-style). Mobile returns the child unchanged.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.order, required this.child});
  final int order;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    if (!isDesktopPlatform) return;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _c = c;
    _fade = CurvedAnimation(parent: c, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 45 * widget.order), () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Centers the settings list to a readable column on desktop; full-width on
/// mobile (unchanged).
class _ProfileScrollFrame extends StatelessWidget {
  const _ProfileScrollFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final UserEntity? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: user == null
            ? _GuestContent(onLogin: () => context.push('/login'))
            : _UserContent(user: user!),
      ),
    );
  }
}

class _GuestContent extends StatelessWidget {
  const _GuestContent({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.25),
                      AppColors.primaryDark.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.primaryLight,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'profile.signin_account_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'profile.signin_account_subtitle'.tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text('profile.sign_in'.tr()),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserContent extends StatelessWidget {
  const _UserContent({required this.user});
  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Avatar(user: user),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayIdentifier,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LogoutButton(),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _confirmLogout(context),
      icon: const Icon(Icons.logout_rounded, size: 20),
      color: AppColors.textSecondary,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surfaceVariant,
        fixedSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'profile.sign_out'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'profile.sign_out_confirm'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
            child: Text(
              'profile.sign_out'.tr(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvidersSection extends StatelessWidget {
  const _ProvidersSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_providers'.tr()),
          const SizedBox(height: 8),
          BlocBuilder<ProviderBloc, ProviderState>(
            builder: (context, state) {
              final currentName = state is ProviderLoaded
                  ? state.currentProvider?.name ?? state.currentProviderId
                  : '—';
              final currentProvider = state is ProviderLoaded
                  ? state.currentProvider
                  : null;

              return _SectionCard(
                children: [
                  _Tile(
                    icon: Icons.movie_filter_outlined,
                    title: 'profile.provider'.tr(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (currentProvider != null &&
                            currentProvider.image.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                currentProvider.image,
                                width: 22,
                                height: 22,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, s) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        Text(
                          currentName,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textHint,
                          size: 20,
                        ),
                      ],
                    ),
                    onTap: () {
                      _ProvidersPage.open(context, context.read<ProviderBloc>());
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String providerGroup(ProviderEntity p) {
  if (p.category == 'cloudstream') return 'cloudstream';
  if (p.category == 'aniyomi') return 'aniyomi';
  if (p.category == 'manga') return 'manga';
  return switch (p.mode) {
    'hybrid' => 'hybrid',
    'client' => 'local',
    _ => 'cloud',
  };
}

String _providerSheetFilter = 'all';

void openProviderPicker(BuildContext context, ProviderBloc bloc) {
  _ProvidersPage.open(context, bloc);
}

class _ProvidersPage extends StatefulWidget {
  const _ProvidersPage();

  static void open(BuildContext context, ProviderBloc bloc) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: const _ProvidersPage(),
        ),
      ),
    );
  }

  @override
  State<_ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<_ProvidersPage> {
  late String _selectedCategory;
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final hasFavorites =
        getIt<HiveService>().getFavoriteProviders().isNotEmpty;
    var initial = _providerSheetFilter;
    if (initial == 'favorites' && !hasFavorites) initial = 'all';
    if (initial == 'all' && hasFavorites) initial = 'favorites';
    _selectedCategory = initial;
    _providerSheetFilter = initial;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite(String id) async {
    await getIt<HiveService>().toggleFavoriteProvider(id);
    if (!mounted) return;
    if (_selectedCategory == 'favorites' &&
        getIt<HiveService>().getFavoriteProviders().isEmpty) {
      _selectedCategory = 'all';
      _providerSheetFilter = 'all';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('profile.choose_provider'.tr()),
        actions: [
          BlocBuilder<ProviderBloc, ProviderState>(
            builder: (context, state) => state is ProviderLoaded
                ? Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _CategoryFilterButton(
                      providers: state.providers,
                      selected: _selectedCategory,
                      onSelected: (cat) => setState(() {
                        _selectedCategory = cat;
                        _providerSheetFilter = cat;
                      }),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: BlocBuilder<ProviderBloc, ProviderState>(
        builder: (context, state) {
          final filtered = state is ProviderLoaded
              ? _filteredProviders(state.providers)
              : const <ProviderEntity>[];
          final favorites =
              getIt<HiveService>().getFavoriteProviders().toSet();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 200),
                      () {
                        if (mounted) setState(() => _query = v.trim());
                      },
                    );
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'profile.search_providers_hint'.tr(),
                    hintStyle: const TextStyle(color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textHint, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear,
                                color: AppColors.textHint, size: 20),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (state is ProviderLoaded && state.offline)
                _ProvidersOfflineBanner(
                  usableCount: state.usableProviders.length,
                  cachedAt: state.cachedAt,
                  onRetry: () =>
                      context.read<ProviderBloc>().add(const ProviderLoad()),
                ),
              if (state is ProviderLoaded)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 6),
                    child: Text(
                      'profile.count_of_total_shown'.tr(args: [
                        '${filtered.length}',
                        '${state.providers.length}'
                      ]),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 12),
                    ),
                  ),
                ),
              Expanded(
                child: switch (state) {
                  ProviderLoaded() => filtered.isEmpty
                      ? const _ProvidersEmpty()
                      : _ProvidersList(
                          providers: filtered,
                          currentProviderId: state.currentProviderId,
                          bottomPad: bottomPad,
                          favorites: favorites,
                          onToggleFavorite: _toggleFavorite,
                          unavailableIds: {
                            for (final p in state.providers)
                              if (!state.isUsable(p)) p.id,
                          },
                        ),
                  ProviderError() => _ProvidersError(
                    onRetry: () =>
                        context.read<ProviderBloc>().add(const ProviderLoad()),
                  ),
                  _ => const _ProvidersLoading(),
                },
              ),
            ],
          );
        },
      ),
    );
  }

  List<ProviderEntity> _filteredProviders(List<ProviderEntity> all) {
    Iterable<ProviderEntity> list;
    if (_selectedCategory == 'favorites') {
      final favs = getIt<HiveService>().getFavoriteProviders().toSet();
      list = all.where((p) => favs.contains(p.id));
    } else if (_selectedCategory == 'all') {
      list = all.where((p) =>
          providerGroup(p) != 'cloudstream' &&
          providerGroup(p) != 'aniyomi' &&
          providerGroup(p) != 'manga');
    } else if (_selectedCategory.startsWith('repo:')) {
      final repo = _selectedCategory.substring(5);
      list = all.where(
          (p) => providerGroup(p) == 'cloudstream' && p.description == repo);
    } else {
      list = all.where((p) => providerGroup(p) == _selectedCategory);
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q));
    }
    return list.toList();
  }
}

class _CategoryFilterButton extends StatelessWidget {
  const _CategoryFilterButton({
    required this.providers,
    required this.selected,
    required this.onSelected,
  });

  final List<ProviderEntity> providers;
  final String selected;
  final ValueChanged<String> onSelected;

  static const _canonicalOrder = [
    'favorites',
    'cloud',
    'hybrid',
    'local',
    'cloudstream',
    'aniyomi',
    'manga'
  ];

  static const _meta = <String, (String, IconData)>{
    'all':        ('All',         Icons.apps_rounded),
    'favorites':  ('Favorites',   Icons.star),
    'cloud':      ('Cloud',       Icons.cloud_outlined),
    'hybrid':     ('Hybrid',      Icons.sync_rounded),
    'local':      ('Local',       Icons.smartphone_outlined),
    'cloudstream':('CloudStream', Icons.extension_outlined),
    'aniyomi':    ('Aniyomi',     Icons.play_circle_outline),
    'manga':      ('Manga',       Icons.menu_book_outlined),
  };

  String _label(String key) =>
      key == 'favorites' ? 'profile.favorites'.tr() : (_meta[key]?.$1 ?? key);

  String _repoShort(String repo) {
    final seg = repo.contains('/') ? repo.split('/').last : repo;
    return seg.length > 18 ? '${seg.substring(0, 17)}…' : seg;
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final p in providers) {
      final g = providerGroup(p);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final favIds = getIt<HiveService>().getFavoriteProviders().toSet();
    final favoriteCount = providers.where((p) => favIds.contains(p.id)).length;
    if (favoriteCount > 0) counts['favorites'] = favoriteCount;
    final repoCounts = <String, int>{};
    for (final p in providers) {
      if (providerGroup(p) != 'cloudstream') continue;
      final r = p.description;
      if (r.isEmpty || r == 'CloudStream') continue;
      repoCounts[r] = (repoCounts[r] ?? 0) + 1;
    }
    final available = _canonicalOrder.where(counts.containsKey).toList();
    final repos = repoCounts.keys.toList()..sort();
    if (available.length < 2 && repos.isEmpty) return const SizedBox.shrink();

    final (String, IconData) selectedMeta = selected.startsWith('repo:')
        ? (_repoShort(selected.substring(5)), Icons.folder_outlined)
        : (_label(selected), (_meta[selected] ?? _meta['all']!).$2);
    final selectedCount = selected == 'all'
        ? providers.length
        : selected.startsWith('repo:')
            ? (repoCounts[selected.substring(5)] ?? 0)
            : (counts[selected] ?? 0);

    final entries = <(String, String, IconData, int)>[
      ('all', _meta['all']!.$1, _meta['all']!.$2, providers.length),
      ...available.map((cat) {
        final meta = _meta[cat] ?? (cat, Icons.label_outline);
        return (cat, _label(cat), meta.$2, counts[cat] ?? 0);
      }),
      ...repos.map((r) =>
          ('repo:$r', _repoShort(r), Icons.folder_outlined, repoCounts[r] ?? 0)),
    ];

    return PopupMenuButton<String>(
      tooltip: 'search.filter'.tr(),
      offset: const Offset(0, 44),
      color: AppColors.surfaceVariant,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (id, label, icon, count) in entries)
          PopupMenuItem<String>(
            value: id,
            height: 42,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected == id
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected == id
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: selected == id
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selectedMeta.$2, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              selectedMeta.$1,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$selectedCount',
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProvidersList extends StatefulWidget {
  const _ProvidersList({
    required this.providers,
    required this.currentProviderId,
    required this.bottomPad,
    required this.favorites,
    required this.onToggleFavorite,
    this.unavailableIds = const {},
  });

  final List<ProviderEntity> providers;
  final String currentProviderId;
  final double bottomPad;
  final Set<String> favorites;
  final ValueChanged<String> onToggleFavorite;

  /// Providers that exist in the list but cannot serve content right now
  /// (server-backed entries while the backend is unreachable).
  final Set<String> unavailableIds;

  @override
  State<_ProvidersList> createState() => _ProvidersListState();
}

class _ProvidersListState extends State<_ProvidersList> {
  static const double _estItemExtent = 72.0;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final i = widget.providers.indexWhere((p) => p.id == widget.currentProviderId);
    final offset = i > 2 ? (i * _estItemExtent - 80).clamp(0.0, double.infinity) : 0.0;
    _controller = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPad + 16),
      addAutomaticKeepAlives: false,
      itemExtent: _estItemExtent,
      itemCount: widget.providers.length,
      itemBuilder: (context, i) {
        final provider = widget.providers[i];
        final selected = provider.id == widget.currentProviderId;
        final unavailable = widget.unavailableIds.contains(provider.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ProviderListTile(
            provider: provider,
            selected: selected,
            isFavorite: widget.favorites.contains(provider.id),
            unavailable: unavailable,
            onToggleFavorite: () => widget.onToggleFavorite(provider.id),
            onTap: () {
              // Refuse the selection outright rather than letting it fail
              // three screens later inside a home or detail request.
              if (unavailable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('profile.provider_needs_server'.tr()),
                    backgroundColor: AppColors.surface,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
                return;
              }
              context.read<ProviderBloc>().add(ProviderSelect(provider.id));
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }
}

class _ProvidersEmpty extends StatelessWidget {
  const _ProvidersEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 44,
              color: AppColors.textHint.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              'profile.no_providers_in_category'.tr(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'profile.try_select_all'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textHint.withValues(alpha: 0.85),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.provider,
    required this.selected,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
    this.unavailable = false,
  });

  final ProviderEntity provider;
  final bool selected;
  final bool isFavorite;
  final bool unavailable;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  bool get _canSolveCloudflare =>
      provider.id.startsWith('an:') ||
      provider.id.startsWith('mn:') ||
      provider.id.startsWith('cs:');

  Future<void> _solveCloudflare(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await requestCloudflareSolve(context, provider.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '${'general.done'.tr()} ✓' : 'general.cancel'.tr()),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unavailable ? 0.45 : 1,
      child: _tile(context),
    );
  }

  Widget _tile(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: AppColors.primary, width: 1.2)
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress:
              _canSolveCloudflare ? () => _solveCloudflare(context) : null,
          onSecondaryTap:
              _canSolveCloudflare ? () => _solveCloudflare(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _ProviderLogo(provider: provider, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.name,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (unavailable)
                            const _ServerDownBadge()
                          else
                            _ProviderModeBadge(mode: provider.mode),
                          if (provider.requiresCfBypass) ...[
                            const SizedBox(width: 4),
                            const _CfBypassBadge(),
                          ],
                          if (provider.nsfw) ...[
                            const SizedBox(width: 4),
                            const _NsfwBadge(),
                          ],
                        ],
                      ),
                      if (provider.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          provider.description,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? Colors.amber : AppColors.textHint,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  tooltip: 'profile.add_favorite'.tr(),
                ),
                const SizedBox(width: 2),
                if (selected)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the mode badge on a server-backed provider while the API is down,
/// so the reason it is greyed out is readable at a glance.
class _ServerDownBadge extends StatelessWidget {
  const _ServerDownBadge();

  @override
  Widget build(BuildContext context) {
    const color = AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            'profile.offline_badge'.tr(),
            style: const TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains the outage in place, above a list that is still partly usable.
class _ProvidersOfflineBanner extends StatelessWidget {
  const _ProvidersOfflineBanner({
    required this.usableCount,
    required this.cachedAt,
    required this.onRetry,
  });

  final int usableCount;
  final DateTime? cachedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'profile.offline_title'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  usableCount > 0
                      ? 'profile.offline_local_available'
                          .tr(args: ['$usableCount'])
                      : 'profile.offline_no_local'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (cachedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'profile.offline_cached_at'.tr(args: [_stamp(cachedAt!)]),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text('general.retry'.tr()),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }
}

class _ProviderModeBadge extends StatelessWidget {
  const _ProviderModeBadge({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    final normalized = mode.toLowerCase();
    final (label, color) = switch (normalized) {
      'client' => ('Local', const Color(0xFF34A853)),
      'hybrid' => ('Hybrid', const Color(0xFFF59E0B)),
      'server' => ('Cloud', const Color(0xFF6B7280)),
      _ => (mode.isEmpty ? 'Cloud' : mode, const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _CfBypassBadge extends StatelessWidget {
  const _CfBypassBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFF38020);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 9, color: color),
          SizedBox(width: 3),
          Text(
            'CF',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _NsfwBadge extends StatelessWidget {
  const _NsfwBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: const Text(
        '18+',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ProvidersLoading extends StatelessWidget {
  const _ProvidersLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppColors.textHint,
      ),
    );
  }
}

/// Reached only when the backend is unreachable, there is no cached list *and*
/// no plugin is installed — i.e. there is genuinely no working path left. The
/// copy therefore points at installing plugins, which needs no server.
class _ProvidersError extends StatelessWidget {
  const _ProvidersError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: AppColors.textSecondary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'profile.offline_title'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'profile.offline_no_local'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      child: Text('general.retry'.tr()),
                    ),
                  ),
                  if (CloudStreamChannel.isSupported) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CloudStreamSourcesPage(),
                          ),
                        ),
                        child: Text('profile.offline_install_plugins'.tr()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchHistorySection extends StatefulWidget {
  const _WatchHistorySection();

  @override
  State<_WatchHistorySection> createState() => _WatchHistorySectionState();
}

class _WatchHistorySectionState extends State<_WatchHistorySection> {
  final HistoryService _historyService = getIt<HistoryService>();
  final DownloadService _downloadService = getIt<DownloadService>();
  int _historyCount = 0;
  int _downloadCount = 0;

  @override
  void initState() {
    super.initState();
    _historyService.revision.addListener(_reload);
    _downloadService.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_reload);
    _downloadService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _historyCount = _historyService.getAll().length;
      _downloadCount = _downloadService.getAll().length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_activity'.tr()),
          const SizedBox(height: 8),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.history_rounded,
                title: 'profile.watch_history'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_historyCount > 0)
                      Text(
                        '$_historyCount',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => context.push('/history'),
              ),
              const Divider(color: AppColors.divider, height: 1),
              _Tile(
                icon: Icons.download_rounded,
                title: 'profile.downloads'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_downloadCount > 0)
                      Text(
                        '$_downloadCount',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => context.push('/downloads'),
              ),
              const Divider(color: AppColors.divider, height: 1),
              _Tile(
                icon: Icons.notifications_active_outlined,
                title: 'Following',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
                onTap: () => context.push('/following'),
              ),
              const Divider(color: AppColors.divider, height: 1),
              _Tile(
                icon: Icons.devices_rounded,
                title: BridgeControl.canHost
                    ? 'profile.share_sources_desktop'.tr()
                    : Platform.isIOS
                        ? 'ios.sources_title'.tr()
                        : 'profile.desktop_sources'.tr(),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
                onTap: () => context.push('/desktop-share'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  late final AppLockRepository _lock = getIt<AppLockRepository>();

  @override
  Widget build(BuildContext context) {
    final enabled = _lock.isEnabled;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('app_lock.section_label'.tr()),
          const SizedBox(height: 8),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.lock_rounded,
                title: 'app_lock.app_lock'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      enabled
                          ? 'app_lock.state_on'.tr()
                          : 'app_lock.state_off'.tr(),
                      style: TextStyle(
                        color: enabled
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                  ],
                ),
                onTap: () async {
                  await context.push('/app-lock-settings');
                  if (mounted) setState(() {});
                },
              ),
              const Divider(color: AppColors.divider, height: 1),
              _Tile(
                icon: Icons.folder_special_rounded,
                title: 'app_lock.private_list'.tr(),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
                onTap: () async {
                  final unlocked = await requestPrivateUnlock(context);
                  if (unlocked && context.mounted) {
                    context.push('/private-list');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection({this.showLabel = true});

  /// When false (the standalone Navigation-bar page), the "APPEARANCE" label
  /// and the redundant inner "Navigation bar" header are hidden.
  final bool showLabel;

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late bool _native = getIt<HiveService>().useNativeTitleBar;
  late String _navStyle = getIt<HiveService>().navStyle;

  Future<void> _toggle(bool value) async {
    setState(() => _native = value);
    await getIt<HiveService>().setUseNativeTitleBar(value);
    await DesktopWindow.setNativeTitleBar(value);
  }

  Future<void> _setNavStyle(String value) async {
    if (value == _navStyle) return;
    setState(() => _navStyle = value);
    await getIt<HiveService>().setNavStyle(value);
    // Push to the shared notifier so the floating nav rebuilds instantly.
    NavPrefs.navStyle.value = value;
  }

  // A tiny realistic mock of each nav style: solid/glass = a floating pill,
  // classic = a full-width bar — with mini tab icons (the first = selected,
  // in a little pill, like the real bar) instead of plain dots.
  Widget _navPreview(String value, Color accent) {
    const icons = [
      Icons.home_rounded,
      Icons.search_rounded,
      Icons.play_arrow_rounded,
      Icons.person_rounded,
    ];
    final muted = accent.withValues(alpha: 0.4);
    Widget miniIcon(int i) {
      if (i == 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 1),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icons[i], size: 9, color: accent),
        );
      }
      return Icon(icons[i], size: 9, color: muted);
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: miniIcon(i),
          ),
      ],
    );

    if (value == 'classic') {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          border: Border(
            top: BorderSide(color: accent.withValues(alpha: 0.4), width: 0.6),
          ),
        ),
        child: row,
      );
    }
    // solid / glass: floating rounded pill
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: value == 'glass'
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.26),
                  accent.withValues(alpha: 0.06),
                ],
              )
            : null,
        color: value == 'solid' ? accent.withValues(alpha: 0.16) : null,
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.8),
      ),
      child: row,
    );
  }

  Widget _navSegment(String value, String labelKey) {
    final selected = _navStyle == value;
    final accent = selected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setNavStyle(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.fromLTRB(6, 9, 6, 7),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: 24, child: Center(child: _navPreview(value, accent))),
              const SizedBox(height: 7),
              Text(labelKey.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLabel) ...[
            _SectionLabel('profile.section_appearance'.tr()),
            const SizedBox(height: 8),
          ],
          _SectionCard(
            children: [
              if (isDesktopPlatform)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _native,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(Icons.web_asset_rounded,
                      color: AppColors.textSecondary),
                  title: Text('profile.native_window_bar'.tr(),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 15)),
                  subtitle: Text('profile.native_window_bar_subtitle'.tr(),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 12)),
                  onChanged: _toggle,
                ),
              if (isMobilePlatform) ...[
                if (widget.showLabel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                  child: Row(
                    children: [
                      const Icon(Icons.dashboard_customize_rounded,
                          size: 18, color: AppColors.textHint),
                      const SizedBox(width: 8),
                      Text('profile.nav_style'.tr(),
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _navSegment('solid', 'profile.nav_style_solid'),
                        _navSegment('glass', 'profile.nav_style_glass'),
                        _navSegment('classic', 'profile.nav_style_classic'),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.view_week_rounded,
                          color: AppColors.textSecondary),
                      title: Text('nav_customize.entry_title'.tr(),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 15)),
                      subtitle: Text('nav_customize.entry_subtitle'.tr(),
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.textHint),
                      onTap: () => showTabCustomizer(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Standalone Navigation-bar settings page (tab-bar style + tab customizer),
/// opened from the Profile "Navigation bar" tile.
class NavbarPage extends StatelessWidget {
  const NavbarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('profile.nav_style'.tr(),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.only(top: 12, bottom: 40),
        child: _AppearanceSection(showLabel: false),
      ),
    );
  }
}

/// Compact Profile entry (matches the security tiles) → opens [AppearancePage].
class _AppearanceEntry extends StatelessWidget {
  const _AppearanceEntry();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        children: [
          _Tile(
            icon: Icons.view_week_rounded,
            title: 'profile.nav_style'.tr(),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
            onTap: () => context.push('/navbar'),
          ),
        ],
      ),
    );
  }
}

/// Compact Profile entry → [PlayerSettingsPage].
///
/// Unconditional, unlike the engine picker it replaced: that was Android-only
/// because every other platform is pinned to one backend, but the page now
/// also owns playback defaults and subtitle appearance, which apply
/// everywhere. The engine block inside is still gated on
/// [canChoosePlayerEngine].
class _PlayerEntry extends StatelessWidget {
  const _PlayerEntry();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        children: [
          _Tile(
            icon: Icons.play_circle_outline_rounded,
            title: 'profile.section_player'.tr(),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
            onTap: () => context.push('/player-settings'),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
    }
  }

  void _showDeveloper(BuildContext context) {
    showAdaptiveModal<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  'https://avatars.githubusercontent.com/u/108933534?v=4',
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 56,
                    height: 56,
                    color: AppColors.primary,
                    child: const Center(
                      child: Text(
                        'AX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Azamov X',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'profile.developer_role'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _open('https://t.me/ackles'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.telegram,
                            color: Color(0xFF2AABEE),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '@ackles',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.open_in_new_rounded,
                            color: AppColors.textHint,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_about'.tr()),
          const SizedBox(height: 8),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.info_outline_rounded,
                title: 'Sozo',
                trailing: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (_, snap) => Text(
                    snap.hasData
                        ? 'v${snap.data!.version} (${snap.data!.buildNumber})'
                        : '…',
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 13),
                  ),
                ),
                onTap: null,
              ),
              Divider(color: AppColors.divider, height: 1),
              _Tile(
                icon: Icons.person_outline_rounded,
                title: 'profile.developer'.tr(),
                trailing: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Azamov X',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => _showDeveloper(context),
              ),
              Divider(color: AppColors.divider, height: 1),
              const _ServerCountdownTile(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SocialIcon(
                icon: Icons.telegram,
                label: 'Telegram',
                onTap: () => _open('https://t.me/sozoApp'),
              ),
              const SizedBox(width: 16),
              _SocialIcon(
                icon: Icons.language_rounded,
                label: 'profile.website'.tr(),
                onTap: () => _open('https://sozo.azamov.me'),
              ),
              const SizedBox(width: 16),
              _SocialIcon(
                icon: Icons.code_rounded,
                label: 'GitHub',
                onTap: () => _open('https://github.com/professorDeveloper'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});
  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoURL;
    final initials = _initials(user.displayIdentifier);

    return Container(
      width: 66,
      height: 66,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => _Initials(initials: initials),
              )
            : _Initials(initials: initials),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isEmpty ? 'S' : name[0].toUpperCase();
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.provider, this.size = 42});
  final ProviderEntity provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: provider.image.isEmpty
          ? _ProviderFallback(name: provider.name, size: size)
          : CachedNetworkImage(
              imageUrl: provider.image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: cache,
              memCacheHeight: cache,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, _) =>
                  _ProviderFallback(name: provider.name, size: size),
              errorWidget: (_, _, _) =>
                  _ProviderFallback(name: provider.name, size: size),
            ),
    );
  }
}

class _ProviderFallback extends StatelessWidget {
  const _ProviderFallback({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}


class _ServerCountdownTile extends StatefulWidget {
  const _ServerCountdownTile();

  @override
  State<_ServerCountdownTile> createState() => _ServerCountdownTileState();
}

class _ServerCountdownTileState extends State<_ServerCountdownTile> {
  static final DateTime _deadline = DateTime.utc(2026, 10, 1);
  late final Timer _timer;
  final _remaining = ValueNotifier<Duration>(Duration.zero);

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final diff = _deadline.difference(DateTime.now().toUtc());
    _remaining.value = diff.isNegative ? Duration.zero : diff;
  }

  @override
  void dispose() {
    _timer.cancel();
    _remaining.dispose();
    super.dispose();
  }

  void _showSupportSheet(BuildContext context) {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServerSupportSheet(remaining: _remaining),
    );
  }

  static String _fmt(Duration rem) {
    final d = rem.inDays;
    final h = rem.inHours.remainder(24);
    final m = rem.inMinutes.remainder(60);
    final s = rem.inSeconds.remainder(60);
    if (d > 0) return '${d}d ${h}h ${m}m';
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSupportSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dns_outlined,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'profile.server'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ValueListenableBuilder<Duration>(
                valueListenable: _remaining,
                builder: (_, rem, _) {
                  return Text(
                    rem == Duration.zero ? 'profile.expired'.tr() : _fmt(rem),
                    style: TextStyle(
                      color: rem == Duration.zero
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerSupportSheet extends StatelessWidget {
  const _ServerSupportSheet({required this.remaining});

  final ValueNotifier<Duration> remaining;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dns_rounded,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'profile.support_title'.tr(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration>(
            valueListenable: remaining,
            builder: (_, rem, _) {
              final expired = rem == Duration.zero;
              if (expired) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'profile.server_expired'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }
              final d = rem.inDays;
              final h = rem.inHours.remainder(24);
              final m = rem.inMinutes.remainder(60);
              final s = rem.inSeconds.remainder(60);
              return Row(
                children: [
                  _SheetCountdownCell(value: d, label: 'profile.days'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: h, label: 'profile.hours'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: m, label: 'profile.min'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: s, label: 'profile.sec'.tr()),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration>(
            valueListenable: remaining,
            builder: (_, rem, _) {
              final expired = rem == Duration.zero;
              return Text(
                expired
                    ? 'profile.support_body_expired'.tr()
                    : 'profile.support_body'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(
                  Uri.parse('https://t.me/ackles'),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.favorite_rounded, size: 18),
              label: Text('profile.support_developer'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetCountdownCell extends StatelessWidget {
  const _SheetCountdownCell({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
