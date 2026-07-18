import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_state.dart';
import 'package:soplay/features/trivia/presentation/bloc/hub/trivia_hub_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/hub/trivia_hub_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/hub/trivia_hub_state.dart';
import 'package:soplay/features/trivia/presentation/widgets/cast_card.dart';

/// The Buff bottom-nav tab: a fan checker. Leads with the Fan Test entry (which
/// borrows real faces from [CastBloc] so the card carries artwork), continues
/// with the "Popular now" people rail, and closes with a single card that pairs
/// the user's daily rank with the leaderboard entry point.
class BuffHubPage extends StatelessWidget {
  const BuffHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => getIt<TriviaHubBloc>()..add(const TriviaHubStarted()),
        ),
        BlocProvider(
          create: (_) => getIt<CastBloc>()..add(const CastStarted()),
        ),
      ],
      child: const _HubView(),
    );
  }
}

class _HubView extends StatelessWidget {
  const _HubView();

  @override
  Widget build(BuildContext context) {
    // Floating nav capsule clearance — same budget as home / My List.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          context.read<TriviaHubBloc>().add(const TriviaHubRefreshed());
          context.read<CastBloc>().add(const CastStarted());
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomInset + 90),
          children: [
            const _Masthead(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _FanTestHero(onTap: () => _openCastPicker(context)),
            ),
            const SizedBox(height: 6),
            const _PopularCastRail(),
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _RankCard(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cast picker is the only way into a round: pick an actor, get tested on
/// their films.
void _openCastPicker(BuildContext context) => context.push('/trivia/cast');

/// Page-title slot (one per screen): wordmark + tagline.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topInset + 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.film_fill,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'navigation.buff'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'trivia.hub_tagline'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The single entry point into a round — Buff is fan-test only. The face stack
/// on the right is pulled from the already-loaded popular cast so the card is
/// carried by real artwork rather than a bare border.
class _FanTestHero extends StatelessWidget {
  const _FanTestHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'trivia.fan_test_title'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'trivia.fan_test_subtitle'.tr(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _FaceStack(),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.play_arrow_solid, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'trivia.start_fan_test'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four overlapping faces from the popular cast. Falls back to a neutral icon
/// tile when the list is empty so the hero row keeps its shape.
class _FaceStack extends StatelessWidget {
  const _FaceStack();

  static const double _face = 36; // photo diameter
  static const double _ring = 2; // separator ring around each face
  static const double _step = 26; // horizontal advance per face
  static const int _max = 4;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CastBloc, CastState>(
      buildWhen: (a, b) => a.status != b.status || a.popular != b.popular,
      builder: (context, state) {
        final loading = state.status == CastStatus.initial ||
            state.status == CastStatus.loadingPopular;
        final people = state.popular.take(_max).toList();

        if (people.isEmpty && !loading) {
          return Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.heart_fill,
              color: AppColors.primaryLight,
              size: 24,
            ),
          );
        }

        final count = people.isEmpty ? _max : people.length;
        const outer = _face + _ring * 2;
        final width = outer + _step * (count - 1);

        return SizedBox(
          width: width,
          height: outer,
          child: Stack(
            children: [
              for (var i = count - 1; i >= 0; i--)
                Positioned(
                  left: i * _step,
                  child: Container(
                    padding: const EdgeInsets.all(_ring),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: people.isEmpty
                        ? const ShimmerWrapper(
                            child: _ShimmerCircle(size: _face),
                          )
                        : _PersonAvatar(
                            url: people[i].profileUrl,
                            name: people[i].name,
                            size: _face,
                            initialSize: 14,
                          ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// "Popular now" actors, straight from [CastBloc] — tapping one skips the
/// picker and opens the actor hero.
class _PopularCastRail extends StatelessWidget {
  const _PopularCastRail();

  // Height budget @ textScale 1.1 (the owner's device):
  //   avatar 72 + gap 8 + name (12.1 * 1.3 * 2 = 31.46) + gap 2
  //   + known-for (11 * 1.25 = 13.75) = 127.21  ->  148 leaves 20.79 (14%).
  // Still clears at textScale 1.5 (143.65), so no hazard stripes.
  static const double _railHeight = 148;
  static const double _itemWidth = 82;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CastBloc, CastState>(
      buildWhen: (a, b) => a.status != b.status || a.popular != b.popular,
      builder: (context, state) {
        final loading = state.status == CastStatus.initial ||
            state.status == CastStatus.loadingPopular;
        if (!loading && state.popular.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'trivia.popular_now'.tr(),
              onTap: () => _openCastPicker(context),
            ),
            SizedBox(
              height: _railHeight,
              child: loading
                  ? ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: 6,
                      itemBuilder: (_, _) => const _RailSlot(
                        width: _itemWidth,
                        child: _RailSkeleton(),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: state.popular.length,
                      itemBuilder: (_, i) => _RailSlot(
                        width: _itemWidth,
                        child: _RailPerson(person: state.popular[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Fixed-width rail cell. The 5px side margins give a 10px inter-item gap and,
/// with the list's 12px padding, a symmetric 17px gutter on BOTH ends — the
/// missing end padding is what let the last name run off the screen edge.
class _RailSlot extends StatelessWidget {
  const _RailSlot({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      child: child,
    );
  }
}

class _RailPerson extends StatelessWidget {
  const _RailPerson({required this.person});

  final CastPersonEntity person;

  @override
  Widget build(BuildContext context) {
    final knownFor = person.knownFor
        .where((e) => e.trim().isNotEmpty)
        .take(1)
        .join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/trivia/actor', extra: person),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: CastCard.heroTag(person),
            child: _PersonAvatar(
              url: person.profileUrl,
              name: person.name,
              size: 72,
              initialSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (knownFor.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              knownFor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mirrors [_RailPerson]'s structure: 72 + 8 + 11 + 4 + 10 = 105 <= 142.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ShimmerWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShimmerCircle(size: 72),
          SizedBox(height: 8),
          HomeSkeletonBox(width: 56, height: 11, radius: 4),
          SizedBox(height: 4),
          HomeSkeletonBox(width: 36, height: 10, radius: 4),
        ],
      ),
    );
  }
}

class _ShimmerCircle extends StatelessWidget {
  const _ShimmerCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      ),
    );
  }
}

/// Circular person avatar with the app's neutral grey ring. A missing photo
/// falls back to initials on [AppColors.surfaceVariant] — the same treatment
/// the shipped Detail cast rail uses, so it reads as deliberate.
class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.initialSize,
    this.ringColor,
    this.ringWidth = 1.5,
  });

  final String url;
  final String name;
  final double size;
  final double initialSize;
  final Color? ringColor;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor ?? AppColors.border,
          width: ringWidth,
        ),
      ),
      child: url.trim().isEmpty
          ? _initials()
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              fadeInDuration: const Duration(milliseconds: 140),
              placeholder: (_, _) =>
                  const ShimmerWrapper(child: ColoredBox(color: Colors.white)),
              errorWidget: (_, _, _) => _initials(),
            ),
    );
  }

  Widget _initials() {
    return ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Text(
          _initialsOf(name),
          maxLines: 1,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: initialSize,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Two initials for a two-word name, else the first character, else "?".
String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Canonical section header: sentence case, 17/w800, whole row tappable,
/// trailing chevron (no "See all" text button).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 18, 16, 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 22,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Daily rank and the leaderboard entry point, merged into one card — two thin
/// stacked rectangles were the "unfinished form" complaint.
class _RankCard extends StatelessWidget {
  const _RankCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TriviaHubBloc, TriviaHubState>(
      buildWhen: (a, b) =>
          a.status != b.status || a.myDailyRank != b.myDailyRank,
      builder: (context, state) {
        final rank = state.myDailyRank;
        final loading = state.status == TriviaHubStatus.loading;
        return Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => context.push('/trivia/leaderboard'),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.6),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: _RankRow(rank: rank, loading: loading),
                  ),
                  Container(height: 0.6, color: AppColors.border),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.chart_bar_alt_fill,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'trivia.view_leaderboards'.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textHint,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.loading});

  final LeaderboardEntryEntity? rank;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final entry = rank;
    final ranked = entry != null;

    return Row(
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: loading
              ? const ShimmerWrapper(child: _ShimmerCircle(size: 52))
              : ranked
                  ? _PersonAvatar(
                      url: entry.avatar,
                      name: entry.username,
                      size: 52,
                      initialSize: 18,
                      ringColor: AppColors.primary,
                      ringWidth: 2,
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.game_controller_solid,
                        color: AppColors.textHint,
                        size: 22,
                      ),
                    ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'trivia.my_daily_rank'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                ranked
                    ? 'trivia.rank_value'.tr(args: ['${entry.rank}'])
                    : 'trivia.unranked'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (ranked) ...[
                const SizedBox(height: 3),
                Text(
                  'trivia.correct_of'.tr(args: ['${entry.correctCount}']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (ranked) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              'trivia.points_value'.tr(args: ['${entry.score}']),
              maxLines: 1,
              style: const TextStyle(
                color: AppColors.primaryLight,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
