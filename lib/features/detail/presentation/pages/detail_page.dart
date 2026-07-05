import 'dart:async';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/blocs/detail_bloc/detail_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/episodes_bloc/episodes_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/favorite_bloc/favorite_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/favorite_bloc/favorite_event.dart';
import 'package:soplay/features/detail/presentation/blocs/favorite_bloc/favorite_state.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/private_list/presentation/private_unlock.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_cast_tab.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_comments_tab.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_hero.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_info.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_related.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_screenshots.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_skeleton.dart';
import 'package:showcaseview/showcaseview.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.args});
  final DetailArgs args;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => getIt<DetailBloc>()..add(DetailLoad(args.contentUrl, provider: args.provider)),
        ),
        BlocProvider(create: (_) => getIt<EpisodesBloc>()),
        BlocProvider(create: (_) => getIt<FavoriteBloc>()),
      ],
      child: _DetailScaffold(
        contentUrl: args.contentUrl,
        provider: args.provider,
        autoPlay: args.autoPlay,
        resumeEpisodeIndex: args.resumeEpisodeIndex,
      ),
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.contentUrl,
    this.provider,
    this.autoPlay = false,
    this.resumeEpisodeIndex,
  });
  final String contentUrl;
  final String? provider;
  final bool autoPlay;
  final int? resumeEpisodeIndex;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocListener<DetailBloc, DetailState>(
          listenWhen: (prev, curr) {
            if (curr is! DetailLoaded) return false;
            if (prev is! DetailLoaded) return true;
            return prev.detail.contentUrl != curr.detail.contentUrl ||
                prev.detail.isFavorited != curr.detail.isFavorited;
          },
          listener: (context, state) {
            if (state is DetailLoaded) {
              context.read<FavoriteBloc>().add(
                FavoriteLoad(
                  contentUrl: state.detail.contentUrl,
                  provider: state.detail.provider,
                  isFavorited: state.detail.isFavorited,
                ),
              );
            }
          },
          child: BlocBuilder<DetailBloc, DetailState>(
            builder: (context, state) {
              return switch (state) {
                DetailInitial() || DetailLoading() => Stack(
                  children: [
                    const DetailSkeleton(),
                    _BackOnlyBar(onBack: () => _goBack(context)),
                  ],
                ),
                DetailLoaded(:final detail) =>
                  BlocBuilder<FavoriteBloc, FavoriteState>(
                    builder: (context, favoriteState) {
                      if (favoriteState is FavoriteInitial) {
                        return Stack(
                          children: [
                            const DetailSkeleton(),
                            _BackOnlyBar(onBack: () => _goBack(context)),
                          ],
                        );
                      }
                      return _DetailView(
                        detail: detail,
                        provider: provider,
                        autoPlay: autoPlay,
                        resumeEpisodeIndex: resumeEpisodeIndex,
                      );
                    },
                  ),
                DetailError(:final message) => _ErrorView(
                  message: message,
                  onRetry: () =>
                      context.read<DetailBloc>().add(DetailLoad(contentUrl, provider: provider)),
                  onSolveCloudflare: isCloudflareError(message)
                      ? () async {
                          final bloc = context.read<DetailBloc>();
                          final prov = provider ??
                              getIt<HiveService>().getCurrentProvider();
                          final ok =
                              await requestCloudflareSolve(context, prov);
                          if (ok) {
                            bloc.add(DetailLoad(contentUrl, provider: provider));
                          }
                        }
                      : null,
                  onBack: () => _goBack(context),
                ),
                _ => const SizedBox.shrink(),
              };
            },
          ),
        ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({
    required this.detail,
    this.provider,
    this.autoPlay = false,
    this.resumeEpisodeIndex,
  });
  final DetailEntity detail;
  final String? provider;
  final bool autoPlay;
  final int? resumeEpisodeIndex;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bodyPlayKey = GlobalKey();

  // One-time coachmark teaching the long-press "move to private" gesture on the
  // add button. Scoped per-instance so stacked detail pages never collide with
  // each other (or with the global showcase used on the main page).
  final GlobalKey _listActionShowcaseKey = GlobalKey();
  late final String _showcaseScope = 'detail-private-${identityHashCode(this)}';
  ShowcaseView? _showcaseView;
  bool _privateShowcaseStarted = false;

  final ValueNotifier<double> _collapse = ValueNotifier<double>(0);
  final ValueNotifier<bool> _showPill = ValueNotifier<bool>(false);

  late final List<String> _tabs;
  late final bool _hasCast;
  late final bool _hasShots;
  double _collapseRange = 1;
  bool _autoPlayTriggered = false;

  @override
  void initState() {
    super.initState();
    _hasCast =
        widget.detail.cast.isNotEmpty ||
        (widget.detail.director?.trim().isNotEmpty ?? false);
    _hasShots = widget.detail.screenshots.isNotEmpty;
    _tabs = [
      'Similar',
      if (_hasCast) 'Cast',
      'Comments',
      if (_hasShots) 'Screenshots',
    ];
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _showcaseView = ShowcaseView.register(
      scope: _showcaseScope,
      blurValue: 1.5,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      skipIfTargetNotPresent: true,
      onFinish: _markPrivateShowcaseSeen,
      onDismiss: (_) => _markPrivateShowcaseSeen(),
    );
    if (widget.autoPlay && !_autoPlayTriggered) {
      _autoPlayTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPrimaryAction();
      });
    }
    _maybeShowPrivateShowcase();
  }

  /// Shows the long-press coachmark exactly once, after the detail content (and
  /// therefore the add button) has been laid out. No-op once dismissed/seen, or
  /// when the detail never loads (this state only exists for [DetailLoaded]).
  void _maybeShowPrivateShowcase() {
    if (_privateShowcaseStarted ||
        getIt<HiveService>().hasSeenPrivateShowcase) {
      return;
    }
    _privateShowcaseStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _showcaseView?.startShowCase([_listActionShowcaseKey]);
        // One-time: mark seen the moment it appears so it never shows again,
        // even if the user navigates away without tapping it.
        _markPrivateShowcaseSeen();
      });
    });
  }

  void _markPrivateShowcaseSeen() {
    if (getIt<HiveService>().hasSeenPrivateShowcase) return;
    unawaited(getIt<HiveService>().markPrivateShowcaseSeen());
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    if (mounted) setState(() {});
  }

  double _swipeAccum = 0;

  void _onSwipeStart(DragStartDetails _) {
    _swipeAccum = 0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    _swipeAccum += details.primaryDelta ?? 0;
  }

  void _onSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _swipeAccum;
    final i = _tabController.index;
    final goNext = (velocity < -80) || (distance < -40);
    final goPrev = (velocity > 80) || (distance > 40);
    if (goNext && i < _tabs.length - 1) {
      _tabController.animateTo(i + 1);
    } else if (goPrev && i > 0) {
      _tabController.animateTo(i - 1);
    }
    _swipeAccum = 0;
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final v = (offset / _collapseRange).clamp(0.0, 1.0);
    if ((v - _collapse.value).abs() > 0.005) {
      _collapse.value = v;
    }

    final renderBox =
        _bodyPlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final pos = renderBox.localToGlobal(Offset.zero);
      final topThreshold =
          MediaQuery.paddingOf(context).top + kToolbarHeight - 4;
      final hidden = (pos.dy + renderBox.size.height) < topThreshold;
      if (hidden != _showPill.value) {
        _showPill.value = hidden;
      }
    }
  }

  @override
  void dispose() {
    _showcaseView?.unregister();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _collapse.dispose();
    _showPill.dispose();
    super.dispose();
  }

  // Localized label for a tab. The tokens in [_tabs] stay in English because
  // they double as switch keys in [_buildTabContent] and ValueKeys; only the
  // visible label is translated.
  String _tabLabel(String tab) => switch (tab) {
    'Similar' => 'detail.similar'.tr(),
    'Cast' => 'movie.cast'.tr(),
    'Comments' => 'detail.comments'.tr(),
    'Screenshots' => 'detail.screenshots'.tr(),
    _ => tab,
  };

  Widget _buildTabContent(DetailEntity detail) {
    final tab = _tabs[_tabController.index];
    return KeyedSubtree(
      key: ValueKey('detail-tab-$tab'),
      child: switch (tab) {
        'Similar' => DetailRelatedSection(related: detail.related),
        'Cast' => DetailCastTab(cast: detail.cast, director: detail.director),
        'Comments' => DetailCommentsTab(
          provider: detail.provider,
          contentUrl: detail.contentUrl,
        ),
        'Screenshots' => DetailScreenshotsSection(
          screenshots: detail.screenshots,
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onPrimaryAction() {
    final state = context.read<EpisodesBloc>().state;
    if (state is EpisodesLoading) return;
    context.read<EpisodesBloc>().add(EpisodesLoad(
      widget.detail.contentUrl,
      provider: widget.provider,
    ));
  }

  void _toggleMyList() {
    context.read<FavoriteBloc>().add(
      FavoriteToggle(
        contentUrl: widget.detail.contentUrl,
        provider: widget.detail.provider,
        title: widget.detail.title,
        thumbnail: widget.detail.thumbnail ?? '',
      ),
    );
  }

  Future<void> _onMoveToPrivate() async {
    if (!await requestPrivateUnlock(context)) return;
    if (!mounted) return;

    final detail = widget.detail;
    await getIt<PrivateListService>().add(
      FavoriteEntity(
        provider: detail.provider,
        contentUrl: detail.contentUrl,
        title: detail.title,
        thumbnail: detail.thumbnail ?? '',
      ),
    );
    // Pull it out of the normal list so private items never surface there, then
    // reset the heart/add button to reflect that it's no longer in My List.
    await getIt<MyListLocalDataSource>().removeByUrl(detail.contentUrl);
    // A private item must leave no history trail — drop any existing entries.
    await getIt<HistoryService>().removeByContentUrl(detail.contentUrl);
    if (!mounted) return;
    context.read<FavoriteBloc>().add(
      FavoriteLoad(
        contentUrl: detail.contentUrl,
        provider: detail.provider,
        isFavorited: false,
      ),
    );
    _showSnack('app_lock.moved_to_private'.tr());
  }

  /// Actions for an item that already lives in the private list (the add button
  /// is showing the lock affordance). Mirrors the private-list page sheet.
  void _showPrivateActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  'app_lock.move_to_my_list'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _moveFromPrivateToMyList();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
                title: Text(
                  'app_lock.removed_from_private'.tr(),
                  style: const TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _removeFromPrivate();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _moveFromPrivateToMyList() async {
    final detail = widget.detail;
    await getIt<PrivateListService>().remove(detail.contentUrl);
    await getIt<MyListLocalDataSource>().add(
      FavoriteEntity(
        provider: detail.provider,
        contentUrl: detail.contentUrl,
        title: detail.title,
        thumbnail: detail.thumbnail ?? '',
      ),
    );
    if (!mounted) return;
    context.read<FavoriteBloc>().add(
      FavoriteLoad(
        contentUrl: detail.contentUrl,
        provider: detail.provider,
        isFavorited: true,
      ),
    );
    _showSnack('app_lock.move_to_my_list'.tr());
  }

  Future<void> _removeFromPrivate() async {
    final detail = widget.detail;
    await getIt<PrivateListService>().remove(detail.contentUrl);
    if (!mounted) return;
    context.read<FavoriteBloc>().add(
      FavoriteLoad(
        contentUrl: detail.contentUrl,
        provider: detail.provider,
        isFavorited: false,
      ),
    );
    _showSnack('app_lock.removed_from_private'.tr());
  }

  void _onShare() {
    final params = <String, String>{'url': widget.detail.contentUrl};
    final provider = widget.detail.provider.trim();
    if (provider.isNotEmpty) params['provider'] = provider;
    final link = Uri.https('sozo.azamov.me', '/detail', params).toString();
    Share.share('${widget.detail.title}\n$link');
  }

  void _handlePlayback(PlaybackEntity playback) {
    if (playback.isSerial) {
      if (playback.episodes.isEmpty) {
        _showSnack('detail.no_episodes'.tr());
        return;
      }
      context.push(
        '/episodes',
        extra: EpisodesArgs(
          title: widget.detail.title,
          contentUrl: playback.contentUrl.isNotEmpty
              ? playback.contentUrl
              : widget.detail.contentUrl,
          provider: playback.provider,
          thumbnail: widget.detail.thumbnail,
          episodes: playback.episodes,
          headers: playback.headers,
          page: playback.page,
          size: playback.size,
          total: playback.total,
          totalPages: playback.totalPages,
        ),
      );
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[DETAIL] movie playback — type=${playback.type} '
        'playerSrc=${playback.playerSrc} '
        'sources=${playback.videoSources.length} '
        'ref=${playback.episodes.isNotEmpty ? playback.episodes.first.mediaRef : '-'}',
      );
    }

    final ref =
        playback.episodes.isNotEmpty ? playback.episodes.first.mediaRef : '';
    final needsResolve = playback.type == 'webview-extract' ||
        playback.playerSrc == null ||
        playback.playerSrc!.isEmpty;
    if (needsResolve && ref.isNotEmpty) {
      unawaited(_resolveAndPlayMovie(playback, ref));
      return;
    }

    _playMovieDirect(playback);
  }

  void _playMovieDirect(PlaybackEntity playback) {
    var movieUrl = playback.playerSrc;
    if (movieUrl == null || movieUrl.isEmpty) {
      final sources = playback.videoSources;
      String? pickedUrl;
      for (final s in sources) {
        if (s.isDefault && s.accessible) {
          pickedUrl = s.videoUrl;
          break;
        }
      }
      if (pickedUrl == null) {
        for (final s in sources) {
          if (s.accessible) {
            pickedUrl = s.videoUrl;
            break;
          }
        }
      }
      pickedUrl ??= sources.isNotEmpty ? sources.first.videoUrl : null;
      movieUrl = pickedUrl;
    }
    if (movieUrl == null || movieUrl.isEmpty) {
      _showSnack('detail.no_playable_source'.tr());
      return;
    }
    Duration resumePos = Duration.zero;
    final historyItem = getIt<HistoryService>().get(widget.detail.contentUrl);
    if (historyItem != null) {
      resumePos = Duration(milliseconds: historyItem.positionMs);
    }
    context.push(
      '/player',
      extra: PlayerArgs(
        title: widget.detail.title,
        provider: playback.provider,
        headers: playback.headers,
        contentUrl: widget.detail.contentUrl,
        thumbnail: widget.detail.thumbnail,
        movieUrl: movieUrl,
        type: playback.type,
        videoSources: playback.videoSources,
        resumePosition: resumePos,
        thumbnails: playback.thumbnails,
      ),
    );
  }

  Future<void> _resolveAndPlayMovie(PlaybackEntity playback, String ref) async {
    // Cancellable while resolving: Esc (desktop), a barrier tap, or the Cancel
    // button dismisses it and aborts the play attempt. `dialogOpen` tracks
    // whether it's still up so a cancel doesn't pop the page underneath (the
    // earlier orphan bug — now Esc pops the real Navigator, so this is safe).
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      // Only the Cancel button (or Esc, via the Navigator) aborts it — a stray
      // click on the dimmed background must NOT cancel the resolve.
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dctx) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: Text('general.cancel'.tr(),
                  style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false);

    final result = await getIt<ResolveMediaUseCase>()(
      ref: ref,
      provider: playback.provider,
    );
    if (!mounted) return;
    // Cancelled while resolving — don't play, and don't pop the page.
    if (!dialogOpen) return;
    Navigator.of(context, rootNavigator: true).pop();

    switch (result) {
      case Success(:final value):
        if (value.videoUrl.isEmpty) {
          _playMovieDirect(playback);
          return;
        }
        Duration resumePos = Duration.zero;
        final historyItem =
            getIt<HistoryService>().get(widget.detail.contentUrl);
        if (historyItem != null) {
          resumePos = Duration(milliseconds: historyItem.positionMs);
        }
        context.push(
          '/player',
          extra: PlayerArgs(
            title: widget.detail.title,
            provider: playback.provider,
            headers: value.headers,
            contentUrl: widget.detail.contentUrl,
            thumbnail: widget.detail.thumbnail,
            movieUrl: value.videoUrl,
            type: value.type,
            videoSources: value.videoSources,
            resumePosition: resumePos,
            thumbnails: value.thumbnails,
          ),
        );
      case Failure(:final error):
        _showSnack(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final screenH = MediaQuery.sizeOf(context).height;
    final heroHeight = (screenH * 0.55).clamp(320.0, 440.0);
    const toolbarHeight = kToolbarHeight;
    _collapseRange = heroHeight - toolbarHeight;

    final detail = widget.detail;

    return MultiBlocListener(
      listeners: [
        BlocListener<EpisodesBloc, EpisodesState>(
          listenWhen: (prev, curr) => prev.runtimeType != curr.runtimeType,
          listener: (context, state) {
            if (state is EpisodesLoaded) {
              _handlePlayback(state.playback);
              context.read<EpisodesBloc>().add(const EpisodesReset());
            } else if (state is EpisodesError) {
              _showSnack(state.message);
              context.read<EpisodesBloc>().add(const EpisodesReset());
            }
          },
        ),
        BlocListener<FavoriteBloc, FavoriteState>(
          listenWhen: (prev, curr) {
            if (prev is FavoriteReady && curr is FavoriteReady) {
              return prev.isLoading &&
                  !curr.isLoading &&
                  prev.isInList == curr.isInList;
            }
            return false;
          },
          listener: (context, state) {
            if (state is FavoriteReady) {
              _showSnack(
                state.isInList
                    ? 'detail.added_to_my_list'.tr()
                    : 'detail.removed_from_my_list'.tr(),
              );
            }
          },
        ),
      ],
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: heroHeight + topPad,
                collapsedHeight: toolbarHeight,
                pinned: true,
                backgroundColor: AppColors.background,
                automaticallyImplyLeading: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: toolbarHeight,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  stretchModes: const [StretchMode.zoomBackground],
                  background: ValueListenableBuilder<double>(
                    valueListenable: _collapse,
                    builder: (_, c, _) => Opacity(
                      opacity: (1 - c).clamp(0.0, 1.0),
                      child: DetailHeroBackground(
                        thumbnail: detail.thumbnail,
                        title: detail.title,
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: DetailContentHeader(
                  detail: detail,
                  onPrimaryAction: _onPrimaryAction,
                  playButtonKey: _bodyPlayKey,
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textHint,
                    dividerColor: Colors.transparent,
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                    padding: EdgeInsets.zero,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    tabs: _tabs.map((t) => Tab(text: _tabLabel(t))).toList(),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: MediaQuery.paddingOf(context).bottom + 32,
                ),
                sliver: SliverToBoxAdapter(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _onSwipeStart,
                    onHorizontalDragUpdate: _onSwipeUpdate,
                    onHorizontalDragEnd: _onSwipeEnd,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            (MediaQuery.sizeOf(context).height -
                                    topPad -
                                    toolbarHeight -
                                    kTextTabBarHeight -
                                    MediaQuery.paddingOf(context).bottom -
                                    36)
                                .clamp(0.0, double.infinity),
                      ),
                      child: _buildTabContent(detail),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: BlocBuilder<FavoriteBloc, FavoriteState>(
              buildWhen: (a, b) {
                if (a is FavoriteReady && b is FavoriteReady) {
                  return a.isInList != b.isInList ||
                      a.isLoading != b.isLoading ||
                      a.inPrivate != b.inPrivate;
                }
                return a.runtimeType != b.runtimeType;
              },
              builder: (context, favState) {
                final isInList = favState is FavoriteReady && favState.isInList;
                final inPrivate =
                    favState is FavoriteReady && favState.inPrivate;
                final showListAction = favState is FavoriteReady;
                final listActionLoading =
                    favState is FavoriteReady && favState.isLoading;
                return ValueListenableBuilder<double>(
                  valueListenable: _collapse,
                  builder: (_, c, _) => ValueListenableBuilder<bool>(
                    valueListenable: _showPill,
                    builder: (_, showPill, _) =>
                        BlocBuilder<EpisodesBloc, EpisodesState>(
                          buildWhen: (a, b) =>
                              (a is EpisodesLoading) != (b is EpisodesLoading),
                          builder: (context, state) => _AnimatedTopBar(
                            collapse: c,
                            showPill: showPill,
                            title: detail.title,
                            isInList: isInList,
                            inPrivate: inPrivate,
                            isLoading: state is EpisodesLoading,
                            showListAction: showListAction,
                            isListActionLoading: listActionLoading,
                            listActionShowcaseKey: _listActionShowcaseKey,
                            showcaseScope: _showcaseScope,
                            onBack: _goBack,
                            onPrimaryAction: _onPrimaryAction,
                            onAddToList: _toggleMyList,
                            onMoveToPrivate: _onMoveToPrivate,
                            onPrivateActions: _showPrivateActions,
                            onShare: _onShare,
                          ),
                        ),
                  ),
                );
              },
            ),
          ),
          BlocBuilder<EpisodesBloc, EpisodesState>(
            buildWhen: (a, b) =>
                (a is EpisodesLoading) != (b is EpisodesLoading),
            builder: (_, state) {
              if (state is! EpisodesLoading) return const SizedBox.shrink();
              return const _PlaybackLoadingOverlay();
            },
          ),
        ],
      ),
    );
  }
}

class _PlaybackLoadingOverlay extends StatelessWidget {
  const _PlaybackLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: const Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedTopBar extends StatelessWidget {
  const _AnimatedTopBar({
    required this.collapse,
    required this.showPill,
    required this.title,
    required this.isInList,
    required this.inPrivate,
    required this.isLoading,
    required this.showListAction,
    required this.isListActionLoading,
    required this.listActionShowcaseKey,
    required this.showcaseScope,
    required this.onBack,
    required this.onPrimaryAction,
    required this.onAddToList,
    required this.onMoveToPrivate,
    required this.onPrivateActions,
    required this.onShare,
  });

  final double collapse;
  final bool showPill;
  final String title;
  final bool isInList;
  final bool inPrivate;
  final bool isLoading;
  final bool showListAction;
  final bool isListActionLoading;
  final GlobalKey listActionShowcaseKey;
  final String showcaseScope;
  final VoidCallback onBack;
  final VoidCallback onPrimaryAction;
  final VoidCallback onAddToList;
  final VoidCallback onMoveToPrivate;
  final VoidCallback onPrivateActions;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final solidOpacity = Curves.easeIn.transform(collapse).clamp(0.0, 1.0);
    final titleOpacity = ((collapse - 0.6) / 0.3).clamp(0.0, 1.0);

    return Stack(
      children: [
        IgnorePointer(
          child: Opacity(
            opacity: solidOpacity,
            child: Container(
              height: topPad + kToolbarHeight,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.96),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.divider.withValues(alpha: solidOpacity),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topPad + 6, left: 8, right: 8),
          child: SizedBox(
            height: kToolbarHeight - 12,
            child: Row(
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: onBack,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Opacity(
                    opacity: titleOpacity,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.25, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: showPill
                      ? Padding(
                          key: const ValueKey('pill'),
                          padding: const EdgeInsets.only(right: 8),
                          child: _ActionPill(
                            onTap: onPrimaryAction,
                            isLoading: isLoading,
                          ),
                        )
                      : const SizedBox(key: ValueKey('no-pill'), width: 0),
                ),
                if (showListAction) ...[
                  Showcase(
                    key: listActionShowcaseKey,
                    scope: showcaseScope,
                    description: 'app_lock.private_long_press_hint'.tr(),
                    targetBorderRadius: BorderRadius.circular(18),
                    targetPadding: const EdgeInsets.all(4),
                    child: _CircleIconButton(
                      icon: isListActionLoading
                          ? Icons.more_horiz_rounded
                          : inPrivate
                          ? Icons.lock_rounded
                          : isInList
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                      iconColor: inPrivate ? AppColors.rating : Colors.white,
                      onTap: isListActionLoading
                          ? null
                          : inPrivate
                          ? onPrivateActions
                          : onAddToList,
                      onLongPress: isListActionLoading || inPrivate
                          ? null
                          : onMoveToPrivate,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _CircleIconButton(
                  icon: Icons.ios_share_rounded,
                  onTap: onShare,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.iconColor = Colors.white,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: onTap,
      onLongPress: onLongPress,
      // Desktop: right-click mirrors the long-press action (e.g. move-to-private).
      onSecondaryTap: onLongPress,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 36,
            height: 36,
            color: Colors.black.withValues(alpha: 0.42),
            child: Icon(icon, color: iconColor, size: 18),
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.onTap, required this.isLoading});
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              else
                const Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: Colors.black,
                ),
              const SizedBox(width: 4),
              Text(
                'detail.play'.tr(),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          SizedBox(
            height: tabBar.preferredSize.height,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: tabBar,
            ),
          ),
          Container(height: 0.5, color: AppColors.divider),
        ],
      ),
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height + 0.5;

  @override
  double get minExtent => tabBar.preferredSize.height + 0.5;

  @override
  bool shouldRebuild(_TabBarDelegate old) => tabBar != old.tabBar;
}

class _BackOnlyBar extends StatelessWidget {
  const _BackOnlyBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topPad + 8,
      left: 8,
      child: HoverTap(
        onTap: onBack,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.45),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 17,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
    this.onSolveCloudflare,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final Future<void> Function()? onSolveCloudflare;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: topPad + 8),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceVariant,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textPrimary,
                    size: 17,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.textHint,
            size: 52,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onRetry, child: Text('general.retry'.tr())),
          if (onSolveCloudflare != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onSolveCloudflare,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
              ),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: Text('cloudflare.solve'.tr()),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}
