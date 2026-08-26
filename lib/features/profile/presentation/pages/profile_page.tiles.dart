// ignore_for_file: unused_element
part of 'profile_page.dart';

/// The shared building blocks every section is drawn from — card, label, tile,
/// divider, chevrons.
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

/// A section heading, with the same accent tick Home puts in front of every
/// row title. Two jobs: it carries the chosen colour down a screen that is
/// otherwise all greys, and it gives a long settings list a visual rhythm so
/// the sections read as separate rather than as one endless column.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.featureIds = const []});

  final String label;

  /// Feature ids sitting under this heading.
  ///
  /// Carries the badge up one level: a NEW mark that only exists on the row
  /// itself is invisible until you have already scrolled to it, which is no
  /// help at all on a page this long. A dot on the heading is what makes
  /// someone look inside.
  final List<String> featureIds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 2.5,
            height: 11,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.5),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          if (featureIds.isNotEmpty) _NewDot(ids: featureIds),
        ],
      ),
    );
  }
}

/// A Profile row. Metrics are the ones in `settings_tiles.dart` so a row here
/// and a row on the page it opens sit on the same grid.
/// A small accent dot, shown when anything under a heading is unseen.
class _NewDot extends StatelessWidget {
  const _NewDot({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: WhatsNew.revision,
      builder: (context, _, _) {
        if (!WhatsNew.anyNew(ids)) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(left: 6),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    this.icon,
    this.leading,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.featureId,
  });

  final IconData? icon;

  /// Signing out is the one row on this page that undoes something, and a row
  /// that reads exactly like "Appearance" gives no sign of that.
  final bool destructive;

  /// Drawn in place of the icon chip, in the same 34px box so the column of
  /// leading marks does not shift between rows.
  final Widget? leading;
  final String title;
  final String? subtitle;

  /// Marks this row as something the viewer has not met yet.
  ///
  /// A registered id shows a NEW badge until the row is opened. See
  /// [WhatsNew]: the app gained torrent search, an in-player source switch, a
  /// Live TV guide and backup without a single surface telling anyone they had
  /// arrived.
  final String? featureId;

  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Opening the row is what clears its badge — not merely scrolling
          // past it, which would mean a feature could be marked "met" by
          // someone who never saw the word.
          final id = featureId;
          if (id != null) WhatsNew.markSeen(id);
          onTap?.call();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                _TileLeading(
                  icon: icon,
                  destructive: destructive,
                  child: leading,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: destructive
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: destructive
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (featureId != null) _NewBadge(id: featureId!),
                        ],
                      ),
                      if (sub != null && sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Half the row at most: past that the value wins the tug of
                // war with the title and pushes it into a wrapped column.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.5,
                  ),
                  child: trailing,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileLeading extends StatelessWidget {
  const _TileLeading({this.icon, this.child, this.destructive = false});

  final IconData? icon;
  final Widget? child;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final custom = child;
    if (custom != null) {
      return SizedBox(width: 34, height: 34, child: custom);
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: destructive
            ? AppColors.error.withValues(alpha: 0.12)
            : AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: icon == null
          ? null
          : Icon(
              icon,
              color: destructive ? AppColors.error : AppColors.textSecondary,
              size: 18,
            ),
    );
  }
}

/// Inset to the title column, like [SettingsDivider] on the sub-pages.
class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(color: AppColors.divider, height: 1, indent: 64);
}

/// Chevron with the accent in front of it, for the Appearance row.
///
/// The row's whole subject is a colour, so the current one belongs on the row —
/// it turns "Appearance ›" into an answer as well as a destination.
class _AccentDotChevron extends StatelessWidget {
  const _AccentDotChevron();

  @override
  Widget build(BuildContext context) {
    final accent = getIt<ThemeController>().accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: accent.base,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const _TileChevron(),
      ],
    );
  }
}

/// Chevron used by every row that opens something.
class _TileChevron extends StatelessWidget {
  const _TileChevron();

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.chevron_right_rounded,
    color: AppColors.textHint,
    size: 20,
  );
}

class _TileLogo extends StatelessWidget {
  const _TileLogo({required this.url, required this.fallback});

  final String url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final cache = (34 * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        memCacheWidth: cache,
        memCacheHeight: cache,
        placeholder: (_, _) => _TileLeading(icon: fallback),
        errorWidget: (_, _, _) => _TileLeading(icon: fallback),
      ),
    );
  }
}


/// The "NEW" mark on a row for a feature the viewer has not opened yet.
///
/// Collapses to nothing once [WhatsNew] no longer considers the id new, which
/// is why it listens rather than reading once: the row it sits on is stateless
/// and would otherwise keep the badge until the page was rebuilt for some
/// unrelated reason.
class _NewBadge extends StatelessWidget {
  const _NewBadge({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: WhatsNew.revision,
      builder: (context, _, _) {
        if (!WhatsNew.isNew(id)) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(left: 7),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            'general.new_badge'.tr(),
            style: TextStyle(
              color: AppColors.onPrimary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        );
      },
    );
  }
}


