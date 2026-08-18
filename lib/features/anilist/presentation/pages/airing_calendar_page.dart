import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/controllers/airing_calendar_controller.dart';
import 'package:soplay/features/anilist/presentation/controllers/anilist_library_controller.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// What airs this week, across all of AniList.
///
/// The complement to Upcoming, which is deliberately narrow — only the shows
/// you already follow. This is the wide view, with a filter back down to yours,
/// so discovering a new season doesn't mean leaving the app.
///
/// Works signed out: the schedule is public. Connecting only adds the "on your
/// list" marks and the filter.
class AiringCalendarPage extends StatefulWidget {
  const AiringCalendarPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<AiringCalendarPage> createState() => _AiringCalendarPageState();
}

class _AiringCalendarPageState extends State<AiringCalendarPage> {
  final AnilistService _service = getIt<AnilistService>();
  late final AiringCalendarController _calendar;
  late final AnilistLibraryController _library;

  @override
  void initState() {
    super.initState();
    _calendar = AiringCalendarController(service: _service);
    _library = AnilistLibraryController(service: _service);
    _calendar.addListener(_onChange);
    _library.addListener(_onLibraryChange);
    _calendar.load();
    if (_service.isConnected) _library.load();
  }

  @override
  void dispose() {
    _calendar.removeListener(_onChange);
    _library.removeListener(_onLibraryChange);
    _calendar.dispose();
    _library.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onLibraryChange() {
    _calendar.setLibrary(_library.entries);
    _onChange();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _WeekStrip(controller: _calendar),
        if (_service.isConnected) _MineFilter(controller: _calendar),
        Expanded(child: _buildDay(context)),
      ],
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Row(
          children: [
            const AnilistLogo(size: 20),
            const SizedBox(width: 9),
            Text(
              'anilist.calendar_title'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _buildDay(BuildContext context) {
    if (_calendar.loading && !_calendar.dayHasAny) {
      return const Center(
        child: CircularProgressIndicator(color: kAnilistBlue, strokeWidth: 2.5),
      );
    }

    Future<void> refresh() => _calendar.load(force: true);
    final airings = _calendar.visible;

    if (airings.isEmpty) {
      // Distinguishing the two cases matters: "nothing airs today" and "nothing
      // of YOURS airs today" send the user to different places.
      final message = _calendar.error ??
          (_calendar.mineOnly && _calendar.dayHasAny
              ? 'anilist.calendar_empty_mine'.tr()
              : 'anilist.calendar_empty'.tr());
      return RefreshIndicator(
        color: kAnilistBlue,
        backgroundColor: AppColors.surface,
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      _calendar.error != null
                          ? Icons.cloud_off_rounded
                          : Icons.event_busy_rounded,
                      size: 46,
                      color: AppColors.textHint.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 13.5,
                        height: 1.5,
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

    return RefreshIndicator(
      color: kAnilistBlue,
      backgroundColor: AppColors.surface,
      onRefresh: refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        itemCount: airings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (context, i) {
          final airing = airings[i];
          return _AiringCard(
            airing: airing,
            mine: _calendar.isMine(airing.media.id),
          );
        },
      ),
    );
  }
}

/// The seven-day selector.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.controller});

  final AiringCalendarController controller;

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.toString();
    final today = AiringCalendarController.startOfDay(DateTime.now());

    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: controller.week.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = controller.week[i];
          final selected = day == controller.selected;
          final isToday = day == today;
          return GestureDetector(
            onTap: () => controller.select(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 54,
              decoration: BoxDecoration(
                color: selected ? kAnilistBlue : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isToday && !selected
                      ? kAnilistBlue.withValues(alpha: 0.55)
                      : Colors.transparent,
                  width: 1.4,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat.E(locale).format(day).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.85)
                          : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// All / my list toggle. Only offered while connected, since it needs a list.
class _MineFilter extends StatelessWidget {
  const _MineFilter({required this.controller});

  final AiringCalendarController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          _FilterPill(
            label: 'anilist.calendar_all'.tr(),
            selected: !controller.mineOnly,
            onTap: () => controller.setMineOnly(false),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: 'anilist.calendar_mine'.tr(),
            selected: controller.mineOnly,
            onTap: () => controller.setMineOnly(true),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? kAnilistBlue.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? kAnilistBlue : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? kAnilistBlue : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AiringCard extends StatelessWidget {
  const _AiringCard({required this.airing, required this.mine});

  final AnilistScheduledAiring airing;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final media = airing.media;
    final title =
        media.englishTitle ?? media.romajiTitle ?? media.nativeTitle ?? '';
    final time = DateFormat.Hm(context.locale.toString()).format(airing.airsAt);
    final aired = airing.hasAired;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mine ? kAnilistBlue.withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Faded once it has gone out, so a glance down the day separates what
          // is still to come from what already aired.
          Opacity(
            opacity: aired ? 0.55 : 1,
            child: AnilistCover(url: media.coverImage, width: 44, radius: 8),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: aired
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 6),
                      const AnilistLogo(size: 15, radius: 4),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'anilist.calendar_episode'.tr(
                    namedArgs: {'episode': '${airing.episode}'},
                  ),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: aired
                  ? AppColors.surfaceVariant
                  : kAnilistBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              time,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: aired ? AppColors.textHint : kAnilistBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
