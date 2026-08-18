import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_link_sheet.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';
import 'package:soplay/features/user_lists/domain/repositories/user_lists_repository.dart';

/// The overflow menu behind the title screen's three-dot button.
///
/// A sheet rather than a [PopupMenuButton] because half of these entries are
/// toggles: the row has to say whether the title is already in Watch Later or
/// tracked on AniList, which a bare menu of labels cannot.
Future<void> showDetailMoreSheet(
  BuildContext context, {
  required FavoriteEntity entity,
  required bool showFollow,
  required bool isFollowing,
  required VoidCallback onToggleFollow,
  required VoidCallback onFindSources,
  required VoidCallback onShare,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DetailMoreSheet(
      entity: entity,
      showFollow: showFollow,
      isFollowing: isFollowing,
      onToggleFollow: onToggleFollow,
      onFindSources: onFindSources,
      onShare: onShare,
    ),
  );
}

class _DetailMoreSheet extends StatefulWidget {
  const _DetailMoreSheet({
    required this.entity,
    required this.showFollow,
    required this.isFollowing,
    required this.onToggleFollow,
    required this.onFindSources,
    required this.onShare,
  });

  final FavoriteEntity entity;
  final bool showFollow;
  final bool isFollowing;
  final VoidCallback onToggleFollow;
  final VoidCallback onFindSources;
  final VoidCallback onShare;

  @override
  State<_DetailMoreSheet> createState() => _DetailMoreSheetState();
}

class _DetailMoreSheetState extends State<_DetailMoreSheet> {
  final UserListSync _listSync = UserListSync();
  late bool _following = widget.isFollowing;

  @override
  void dispose() {
    _listSync.dispose();
    super.dispose();
  }

  void _toggleFollow() {
    setState(() => _following = !_following);
    widget.onToggleFollow();
  }

  void _run(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final anilistReady = getIt<AnilistService>().isConnected &&
        widget.entity.contentUrl.isNotEmpty;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Text(
              widget.entity.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          UserListToggle(
            kind: UserListKind.watchLater,
            entity: widget.entity,
            sync: _listSync,
            builder: (_, active, toggle) => _SheetRow(
              icon: active
                  ? Icons.watch_later_rounded
                  : Icons.watch_later_outlined,
              label: 'detail.watch_later'.tr(),
              active: active,
              onTap: toggle,
            ),
          ),
          UserListToggle(
            kind: UserListKind.watched,
            entity: widget.entity,
            sync: _listSync,
            builder: (_, active, toggle) => _SheetRow(
              icon: active ? Icons.visibility_rounded : Icons.visibility_outlined,
              label: 'detail.watched'.tr(),
              active: active,
              onTap: toggle,
            ),
          ),
          if (widget.showFollow)
            _SheetRow(
              icon: _following
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              label: 'detail.follow_series'.tr(),
              active: _following,
              onTap: _toggleFollow,
            ),
          if (anilistReady) _AnilistRow(entity: widget.entity),
          const Divider(
            color: AppColors.divider,
            height: 17,
            indent: 18,
            endIndent: 18,
          ),
          _SheetRow(
            icon: Icons.travel_explore_rounded,
            label: 'detail.find_other_sources'.tr(),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textHint,
              size: 20,
            ),
            onTap: () => _run(widget.onFindSources),
          ),
          _SheetRow(
            icon: Icons.ios_share_rounded,
            label: 'movie.share'.tr(),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textHint,
              size: 20,
            ),
            onTap: () => _run(widget.onShare),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Fires after any [UserListToggle] writes, so sibling toggles re-read the
/// cache: marking a title Watched evicts it from Watch Later.
class UserListSync extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Holds the membership state of one user-curated list and hands it to
/// [builder], so a circle button and a sheet row share the same logic.
///
/// The repository writes its cache before the network, so the flip is immediate
/// and survives a failed request — no spinner, no rollback dance.
class UserListToggle extends StatefulWidget {
  const UserListToggle({
    super.key,
    required this.kind,
    required this.entity,
    required this.builder,
    this.sync,
  });

  final UserListKind kind;
  final FavoriteEntity entity;
  final UserListSync? sync;
  final Widget Function(BuildContext context, bool active, VoidCallback toggle)
      builder;

  @override
  State<UserListToggle> createState() => _UserListToggleState();
}

class _UserListToggleState extends State<UserListToggle> {
  late bool _active = _read();

  bool _read() => getIt<UserListsRepository>()
      .contains(widget.kind, widget.entity.contentUrl);

  @override
  void initState() {
    super.initState();
    widget.sync?.addListener(_reread);
  }

  @override
  void didUpdateWidget(covariant UserListToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sync != widget.sync) {
      oldWidget.sync?.removeListener(_reread);
      widget.sync?.addListener(_reread);
    }
    // The same toggle is reused when the page rebinds to another title.
    if (oldWidget.entity.contentUrl != widget.entity.contentUrl) {
      _active = _read();
    }
  }

  @override
  void dispose() {
    widget.sync?.removeListener(_reread);
    super.dispose();
  }

  void _reread() {
    final active = _read();
    if (mounted && active != _active) setState(() => _active = active);
  }

  Future<void> _toggle() async {
    final repo = getIt<UserListsRepository>();
    final next = !_active;
    setState(() => _active = next);
    if (next) {
      await repo.add(widget.kind, widget.entity);
    } else {
      await repo.remove(widget.kind, widget.entity.contentUrl);
    }
    if (mounted) widget.sync?.ping();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _active, _toggle);
}

class _AnilistRow extends StatefulWidget {
  const _AnilistRow({required this.entity});

  final FavoriteEntity entity;

  @override
  State<_AnilistRow> createState() => _AnilistRowState();
}

class _AnilistRowState extends State<_AnilistRow> {
  late AnilistLink? _link = getIt<AnilistLinkStore>()
      .get(widget.entity.provider, widget.entity.contentUrl);

  Future<void> _open() async {
    await AnilistLinkSheet.show(
      context,
      provider: widget.entity.provider,
      contentUrl: widget.entity.contentUrl,
      title: widget.entity.title,
    );
    if (!mounted) return;
    setState(() => _link = getIt<AnilistLinkStore>()
        .get(widget.entity.provider, widget.entity.contentUrl));
  }

  @override
  Widget build(BuildContext context) {
    final linked = _link != null;
    return _SheetRow(
      icon: linked ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
      label: linked
          ? 'detail.anilist_tracked'.tr()
          : 'detail.anilist_track'.tr(),
      active: linked,
      accent: kAnilistBlue,
      onTap: _open,
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.accent = AppColors.rating,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 19,
                color: active ? accent : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            trailing ??
                (active
                    ? Icon(Icons.check_rounded, size: 20, color: accent)
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
