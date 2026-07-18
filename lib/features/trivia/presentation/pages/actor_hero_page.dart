import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/actor_profile_entity.dart';
import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/domain/entities/challenge_entity.dart';
import 'package:soplay/features/trivia/domain/entities/top_fan_entity.dart';
import 'package:soplay/features/trivia/domain/usecases/create_challenge_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/get_actor_profile_usecase.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/topfans/top_fans_state.dart';
import 'package:soplay/features/trivia/presentation/pages/top_fans_page.dart';
import 'package:soplay/features/trivia/presentation/trivia_args.dart';
import 'package:soplay/features/trivia/presentation/widgets/cast_card.dart';
import 'package:soplay/features/trivia/presentation/widgets/top_fans_strip.dart';

/// The selected actor / character hero: a full-bleed blurred backdrop, the
/// circular profile that receives the Hero flight from the cast card, a Top Fans
/// preview strip, a filmography rail, and a sticky "Start Fan Test" bottom bar.
class ActorHeroPage extends StatefulWidget {
  const ActorHeroPage({super.key, required this.person});

  final CastPersonEntity person;

  @override
  State<ActorHeroPage> createState() => _ActorHeroPageState();
}

class _ActorHeroPageState extends State<ActorHeroPage> {
  ActorProfileEntity? _profile;
  bool _loading = true;
  String? _error;
  bool _creatingChallenge = false;

  CastPersonEntity get _person => widget.person;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await getIt<GetActorProfileUseCase>()(
      id: _person.id,
      kind: _person.kind,
    );
    if (!mounted) return;
    switch (result) {
      case Success<ActorProfileEntity>(:final value):
        setState(() {
          _profile = value;
          _loading = false;
        });
      case Failure<ActorProfileEntity>(:final error):
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  String get _backdropUrl {
    final film = _profile?.filmography;
    if (film != null && film.isNotEmpty && film.first.poster.isNotEmpty) {
      return film.first.poster;
    }
    return _person.profileUrl;
  }

  int get _titleCount =>
      _profile?.filmography.length ?? _person.knownFor.length;

  void _startFanTest() {
    HapticFeedback.mediumImpact();
    openGame(
      context,
      GameArgs(
        mode: 'fan_test',
        actorRef: ActorRefEntity(
          id: _person.id,
          kind: _person.kind,
          name: _person.name,
          profileUrl: _person.profileUrl,
        ),
      ),
    );
  }

  Future<void> _challengeFriend() async {
    if (_creatingChallenge) return;
    HapticFeedback.lightImpact();
    setState(() => _creatingChallenge = true);
    final result = await getIt<CreateChallengeUseCase>()(
      mode: 'fan_test',
      actorId: _person.id,
      kind: _person.kind,
    );
    if (!mounted) return;
    setState(() => _creatingChallenge = false);
    switch (result) {
      case Success<ChallengeEntity>(:final value):
        final link = value.deepLink.isNotEmpty ? value.deepLink : value.webLink;
        Share.share(
          '${'trivia.challenge_share_text'.tr(namedArgs: {'name': _person.name})}\n$link',
        );
      case Failure<ChallengeEntity>(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
            backgroundColor: AppColors.surface,
          ),
        );
    }
  }

  void _openTopFans() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TopFansPage(actorId: _person.id, kind: _person.kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.paddingOf(context).top;

    return BlocProvider<TopFansBloc>(
      create: (_) => getIt<TopFansBloc>()
        ..add(TopFansRequested(actorId: _person.id, kind: _person.kind)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            _Backdrop(url: _backdropUrl),
            Positioned.fill(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _HeroHead(
                      person: _person,
                      profile: _profile,
                      loading: _loading,
                      titleCount: _titleCount,
                      topSafe: topSafe,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: _TopFansSection(onTap: _openTopFans),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _FilmographySection(
                      loading: _loading,
                      items: _profile?.filmography ?? const [],
                    ),
                  ),
                  if (_error != null && _profile == null)
                    SliverToBoxAdapter(child: _InlineError(message: _error!)),
                  const SliverToBoxAdapter(child: SizedBox(height: 140)),
                ],
              ),
            ),
            _FloatingBack(topSafe: topSafe),
            _StickyBar(
              onStart: _startFanTest,
              onChallenge: _challengeFriend,
              creatingChallenge: _creatingChallenge,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backdrop
// ─────────────────────────────────────────────────────────────────────────────

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 460,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  const ColoredBox(color: AppColors.surfaceVariant),
            )
          else
            const ColoredBox(color: AppColors.surfaceVariant),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: const ColoredBox(color: Color(0x33000000)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00181818),
                  AppColors.background,
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero head (profile circle + name + meta)
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHead extends StatelessWidget {
  const _HeroHead({
    required this.person,
    required this.profile,
    required this.loading,
    required this.titleCount,
    required this.topSafe,
  });

  final CastPersonEntity person;
  final ActorProfileEntity? profile;
  final bool loading;
  final int titleCount;
  final double topSafe;

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? person.name;
    final birthplace = profile?.birthplace ?? '';
    final knownFor = person.knownFor
        .where((e) => e.trim().isNotEmpty)
        .take(2)
        .join(' · ');
    final subtitle = birthplace.isNotEmpty ? birthplace : knownFor;

    return Padding(
      padding: EdgeInsets.only(top: topSafe + 78, left: 24, right: 24),
      child: Column(
        children: [
          SizedBox(
            width: 128,
            height: 128,
            child: Hero(
              tag: CastCard.heroTag(person),
              child: CastAvatar(
                url: person.profileUrl,
                name: name,
                highlightRing: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
              ],
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 10),
            const ShimmerWrapper(
              child: HomeSkeletonBox(width: 160, height: 12, radius: 4),
            ),
          ] else if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _TitlesChip(count: titleCount, loading: loading),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _TitlesChip extends StatelessWidget {
  const _TitlesChip({required this.count, required this.loading});
  final int count;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.film_fill,
              color: AppColors.primaryLight, size: 14),
          const SizedBox(width: 7),
          Text(
            loading
                ? '…'
                : 'trivia.n_titles'.tr(namedArgs: {'count': '$count'}),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top fans section (reads TopFansBloc)
// ─────────────────────────────────────────────────────────────────────────────

class _TopFansSection extends StatelessWidget {
  const _TopFansSection({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TopFansBloc, TopFansState>(
      builder: (context, state) {
        final loading = state.status == TopFansStatus.loading ||
            state.status == TopFansStatus.initial;
        final fans = state.fanStat?.topFans ?? const <TopFanEntity>[];
        final myId = _currentUserId();
        int? myRank;
        if (myId != null) {
          for (final f in fans) {
            if (f.userId == myId) {
              myRank = f.rank;
              break;
            }
          }
        }
        return TopFansStrip(
          topFans: fans,
          myRank: myRank,
          loading: loading,
          onTap: onTap,
        );
      },
    );
  }
}

String? _currentUserId() {
  final state = getIt<AuthBloc>().state;
  return state is AuthLoaded ? state.token.user.id : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Filmography rail
// ─────────────────────────────────────────────────────────────────────────────

class _FilmographySection extends StatelessWidget {
  const _FilmographySection({required this.loading, required this.items});

  final bool loading;
  final List<FilmographyItemEntity> items;

  @override
  Widget build(BuildContext context) {
    if (!loading && items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(
            'trivia.filmography'.tr(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 196,
          child: loading
              ? _railSkeleton()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _PosterCard(item: items[i]),
                ),
        ),
      ],
    );
  }

  Widget _railSkeleton() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, _) => const ShimmerWrapper(
        child: HomeSkeletonBox(width: 116, height: 196, radius: 12),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item});
  final FilmographyItemEntity item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ColoredBox(
                color: AppColors.surfaceVariant,
                child: item.poster.isEmpty
                    ? const Center(
                        child: Icon(CupertinoIcons.film,
                            color: AppColors.textHint, size: 26),
                      )
                    : CachedNetworkImage(
                        imageUrl: item.poster,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const ShimmerWrapper(
                          child: ColoredBox(color: Colors.white),
                        ),
                        errorWidget: (_, _, _) => const Center(
                          child: Icon(CupertinoIcons.film,
                              color: AppColors.textHint, size: 26),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (item.year.isNotEmpty)
            Text(
              item.year,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chrome: back button, sticky CTA bar, inline error
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingBack extends StatelessWidget {
  const _FloatingBack({required this.topSafe});
  final double topSafe;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: topSafe + 8,
      left: 8,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 38,
              height: 38,
              color: Colors.black.withValues(alpha: 0.38),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickyBar extends StatelessWidget {
  const _StickyBar({
    required this.onStart,
    required this.onChallenge,
    required this.creatingChallenge,
  });

  final VoidCallback onStart;
  final VoidCallback onChallenge;
  final bool creatingChallenge;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomSafe),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00181818), AppColors.background],
            stops: [0.0, 0.35],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _PrimaryButton(onTap: onStart),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _SecondaryButton(
                onTap: onChallenge,
                busy: creatingChallenge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryLight, AppColors.primary],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              'trivia.start_fan_test'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.onTap, required this.busy});
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textSecondary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.person_2_fill,
                      color: AppColors.textPrimary, size: 16),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'trivia.challenge_friend'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }
}
