import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/cast/cast_state.dart';
import 'package:soplay/features/trivia/presentation/bloc/hub/trivia_hub_bloc.dart';
import 'package:soplay/features/trivia/presentation/bloc/hub/trivia_hub_event.dart';
import 'package:soplay/features/trivia/presentation/bloc/hub/trivia_hub_state.dart';
import 'package:soplay/features/trivia/presentation/widgets/cast_card.dart';

/// The Buff bottom-nav tab: a fan checker. Leads with actor selection (the
/// Fan Test entry + a "Popular now" cast rail from [CastBloc]) and closes with
/// the current user's daily-rank teaser (loaded by [TriviaHubBloc]).
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
          padding: EdgeInsets.only(bottom: bottomInset + 110),
          children: [
            const _Hero(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _FanTestCard(onTap: () => _openCastPicker(context)),
            ),
            const SizedBox(height: 24),
            const _PopularCastRail(),
            const SizedBox(height: 26),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _RankSection(),
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

class _Hero extends StatelessWidget {
  const _Hero();

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
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'navigation.buff'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
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

/// The single entry point into a round — Buff is fan-test only.
class _FanTestCard extends StatelessWidget {
  const _FanTestCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.heart_fill,
                  color: AppColors.primaryLight,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'trivia.fan_test_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'trivia.fan_test_subtitle'.tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Popular now" actors, straight from [CastBloc] — tapping one skips the
/// picker and opens the actor hero.
class _PopularCastRail extends StatelessWidget {
  const _PopularCastRail();

  static const double _railHeight = 118;
  static const double _itemWidth = 78;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'trivia.popular_now'.tr().toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openCastPicker(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'general.see_all'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: _railHeight,
              child: loading
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: 6,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, _) => const SizedBox(
                        width: _itemWidth,
                        child: CastCardSkeleton(),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: state.popular.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, i) => _RailPerson(
                        person: state.popular[i],
                        width: _itemWidth,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _RailPerson extends StatelessWidget {
  const _RailPerson({required this.person, required this.width});

  final CastPersonEntity person;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/trivia/actor', extra: person),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              height: width,
              child: CastAvatar(url: person.profileUrl, name: person.name),
            ),
            const SizedBox(height: 9),
            Text(
              person.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankSection extends StatelessWidget {
  const _RankSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TriviaHubBloc, TriviaHubState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RankChip(
              rank: state.myDailyRank,
              loading: state.status == TriviaHubStatus.loading,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/trivia/leaderboard'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                icon: const Icon(CupertinoIcons.chart_bar_alt_fill, size: 18),
                label: Text(
                  'trivia.view_leaderboards'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({required this.rank, required this.loading});

  final LeaderboardEntryEntity? rank;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ranked = rank != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ranked
                  ? AppColors.primary.withValues(alpha: 0.16)
                  : AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(
                    ranked
                        ? CupertinoIcons.rosette
                        : CupertinoIcons.game_controller_solid,
                    color: ranked ? AppColors.primaryLight : AppColors.textHint,
                    size: 22,
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
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ranked
                      ? 'trivia.rank_value'.tr(args: ['${rank!.rank}'])
                      : 'trivia.unranked'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (ranked)
            Text(
              'trivia.points_value'.tr(args: ['${rank!.score}']),
              style: const TextStyle(
                color: AppColors.primaryLight,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
