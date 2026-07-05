import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/aniyomi/presentation/pages/aniyomi_sources_page.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/desktop_window.dart';
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
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final headerH = topPad + _headerContentHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Subtle gradient background
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
          RefreshIndicator(
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
                      return _ProfileHeader(user: user);
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                const SliverToBoxAdapter(child: StreakCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(child: _ProvidersSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                // Repo management runs the native DEX plugins, so it only makes
                // sense on the phone (host). On desktop the sources arrive over
                // the bridge and are managed on the phone — hide these there.
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
                const SliverToBoxAdapter(child: _WatchHistorySection()),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(child: _SecuritySection()),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                if (isDesktopPlatform) ...[
                  const SliverToBoxAdapter(child: _AppearanceSection()),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
                const SliverToBoxAdapter(child: _AboutSection()),
                SliverToBoxAdapter(child: SizedBox(height: bottomPad + 96)),
              ],
            ),
          ),
          // Blur header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _headerBlur,
              builder: (_, blur, _) {
                final progress = blur.clamp(0.0, 1.0);
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
                  child: Text(
                    'profile.title'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
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

/// Provider filter group: CloudStream first, otherwise by delivery mode.
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

/// Remembers the last-picked provider filter for the session so reopening the
/// sheet keeps the same view.
String _providerSheetFilter = 'all';

/// Public entry point so other features (e.g. the home top bar quick-switch)
/// can open the otherwise-private full provider picker.
void openProviderPicker(BuildContext context, ProviderBloc bloc) {
  _ProvidersPage.open(context, bloc);
}

/// Full-screen provider picker (replaces the old bottom sheet) with a search box
/// and the category filter. A page scrolls long lists (60+ CloudStream
/// providers) far more comfortably than a draggable sheet.
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
  // Filter group: 'favorites' | 'all' | 'cloud' | 'hybrid' | 'local' |
  // 'cloudstream' | 'aniyomi' | 'manga'.
  late String _selectedCategory;
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // Default to the Favorites view when the user has any starred providers,
    // otherwise fall back to the remembered (or 'all') filter.
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
    // Leaving the Favorites view empty is confusing — drop back to All.
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
        // Kill the Material 3 scroll-under tint (it pulls the seed colour and
        // looked red as content scrolled under the bar).
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
                        _providerSheetFilter = cat; // remember for next open
                      }),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: BlocBuilder<ProviderBloc, ProviderState>(
        builder: (context, state) {
          // Filter once per build (was computed twice — count + list — over 300+
          // providers each frame, the main source of the open jank).
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
                  // Debounce so each keystroke doesn't re-filter 300+ providers
                  // and recompute the category counts on the whole tree.
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
    // "All" excludes CloudStream (its own group). `repo:<name>` shows just one
    // CloudStream repo's providers (their `description` carries the repo name).
    // Otherwise match the delivery-mode group (cloud/hybrid/local) or cloudstream.
    Iterable<ProviderEntity> list;
    if (_selectedCategory == 'favorites') {
      // Favorites span every group (cloud/hybrid/local/cloudstream/aniyomi/manga).
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

/// Compact category filter dropdown shown in the providers sheet header.
/// Defaults to "All"; opens a popup menu listing only categories that have
/// at least one provider (preserving the canonical order tmdb → anime →
/// movies → other).
class _CategoryFilterButton extends StatelessWidget {
  const _CategoryFilterButton({
    required this.providers,
    required this.selected,
    required this.onSelected,
  });

  final List<ProviderEntity> providers;
  final String selected;
  final ValueChanged<String> onSelected;

  // Filter groups: Favorites first (only shown when the user has starred any),
  // then by delivery type (mode) plus CloudStream, per request.
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

  /// Display label for a group — localised for 'favorites', static otherwise.
  String _label(String key) =>
      key == 'favorites' ? 'profile.favorites'.tr() : (_meta[key]?.$1 ?? key);

  /// Short, chip-friendly form of a repo name (drops the GitHub owner, trims).
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
    // Favorites is a virtual group spanning every category; surface it only
    // when the user has starred at least one provider that's still available.
    final favIds = getIt<HiveService>().getFavoriteProviders().toSet();
    final favoriteCount = providers.where((p) => favIds.contains(p.id)).length;
    if (favoriteCount > 0) counts['favorites'] = favoriteCount;
    // Per-repo counts for CloudStream providers (their `description` = repo name).
    final repoCounts = <String, int>{};
    for (final p in providers) {
      if (providerGroup(p) != 'cloudstream') continue;
      final r = p.description;
      if (r.isEmpty || r == 'CloudStream') continue;
      repoCounts[r] = (repoCounts[r] ?? 0) + 1;
    }
    final available = _canonicalOrder.where(counts.containsKey).toList();
    final repos = repoCounts.keys.toList()..sort();
    // Nothing to filter when there's only one category and no repos.
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
      // One entry per CloudStream repo (e.g. "cs-kraptor", "…-phisher").
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
  });

  final List<ProviderEntity> providers;
  final String currentProviderId;
  final double bottomPad;
  final Set<String> favorites;
  final ValueChanged<String> onToggleFavorite;

  @override
  State<_ProvidersList> createState() => _ProvidersListState();
}

class _ProvidersListState extends State<_ProvidersList> {
  // tile (~64) + separator (8); good enough to bring the selected row into view.
  static const double _estItemExtent = 72.0;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    // Open already positioned at the selected provider (via initialScrollOffset)
    // instead of rendering at the top then post-frame jumping — that reposition
    // was the visible "opens late then snaps" lag on the 300+ item list. Any
    // overshoot past maxScrollExtent is clamped by the list on first layout.
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
      // Fixed extent → the list computes any row's offset in O(1), so opening
      // already-scrolled to a far-down selected provider is instant. A variable-
      // extent (ListView.separated) list had to lay out EVERY row above the
      // target to reach it — that was the ~2s open freeze on the 300+ list.
      itemExtent: _estItemExtent,
      itemCount: widget.providers.length,
      itemBuilder: (context, i) {
        final provider = widget.providers[i];
        final selected = provider.id == widget.currentProviderId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ProviderListTile(
            provider: provider,
            selected: selected,
            isFavorite: widget.favorites.contains(provider.id),
            onToggleFavorite: () => widget.onToggleFavorite(provider.id),
            onTap: () {
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
  });

  final ProviderEntity provider;
  final bool selected;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  // Only on-device extension providers (an:/mn:/cs:) sit behind a per-source
  // Cloudflare challenge the interactive solver can pre-clear.
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
          // Desktop: right-click also triggers the Cloudflare solver.
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

/// Hint that the provider sits behind a Cloudflare challenge — the
/// CfBypassInterceptor will silently solve it on first use, so the first call
/// of the session may take a few extra seconds.
class _CfBypassBadge extends StatelessWidget {
  const _CfBypassBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFF38020); // Cloudflare orange
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

/// Small "18+" pill shown for providers flagged adult/NSFW by their repo.
class _NsfwBadge extends StatelessWidget {
  const _NsfwBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFE53935); // red
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

class _ProvidersError extends StatelessWidget {
  const _ProvidersError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.textHint,
            size: 36,
          ),
          const SizedBox(height: 10),
          Text(
            'profile.providers_error'.tr(),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
              onPressed: onRetry, child: Text('general.retry'.tr())),
        ],
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

/// Desktop-only: appearance settings (currently the native-vs-custom title bar).
class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection();

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late bool _native = getIt<HiveService>().useNativeTitleBar;

  Future<void> _toggle(bool value) async {
    setState(() => _native = value);
    await getIt<HiveService>().setUseNativeTitleBar(value);
    await DesktopWindow.setNativeTitleBar(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_appearance'.tr()),
          const SizedBox(height: 8),
          _SectionCard(
            children: [
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
            ],
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
                trailing: const Text(
                  '1.0.0',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13),
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
    // Decode at display size (× DPR), not full resolution. With 60+ provider
    // tiles sharing the same icon URL this keeps the image cache tiny instead
    // of holding dozens of full-res bitmaps (a major OOM/jank source).
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
              // Disk-cached + decoded at display size: with 280+ distinct source
              // icons this avoids re-fetching every scroll/session and keeps the
              // memory cache small (was a jank source on the Aniyomi list).
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

// ─── Server Countdown Tile ──────────────────────────────────────

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
          // Live countdown
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
