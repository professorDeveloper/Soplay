import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:riasdxd/core/di/injection.dart';
import 'package:riasdxd/core/theme/app_colors.dart';
import 'package:riasdxd/features/detail/domain/entities/detail_args.dart';
import 'package:riasdxd/features/tracker/data/follow_service.dart';
import 'package:riasdxd/features/tracker/domain/entities/followed_title.dart';

/// Serials the user follows, with a manual "check for new episodes". A check
/// also runs automatically when the page opens.
class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  final FollowService _service = getIt<FollowService>();
  List<FollowedTitle> _items = const [];
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _items = _service.list();
    // Auto-check on open (bounded + timed inside the service — safe).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_items.isNotEmpty) _check(silent: true);
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final grown = await _service.checkForUpdates();
      if (!mounted) return;
      setState(() => _items = _service.list());
      if (!silent || grown > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(grown > 0
                ? '$grown title(s) have new episodes'
                : 'No new episodes'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _unfollow(FollowedTitle t) async {
    await _service.unfollow(t.contentUrl);
    if (!mounted) return;
    setState(() => _items = _service.list());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: const Text('Following',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              onPressed: _checking ? null : () => _check(),
              tooltip: 'Check for new episodes',
              icon: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _items.isEmpty
          ? _empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _tile(_items[i]),
            ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded,
                  color: AppColors.textHint.withValues(alpha: 0.5), size: 60),
              const SizedBox(height: 14),
              const Text(
                'Follow a series to get notified when new episodes drop.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textHint, fontSize: 14),
              ),
            ],
          ),
        ),
      );

  Widget _tile(FollowedTitle t) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 44,
            height: 60,
            child: t.thumbnail.isNotEmpty
                ? Image.network(t.thumbnail,
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => _ph())
                : _ph(),
          ),
        ),
        title: Text(t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          t.lastEpisodeCount > 0
              ? '${t.lastEpisodeCount} episodes'
              : 'Not checked yet',
          style: const TextStyle(color: AppColors.textHint, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.notifications_off_outlined,
              color: Colors.redAccent),
          tooltip: 'Unfollow',
          onPressed: () => _unfollow(t),
        ),
        onTap: () {
          if (t.contentUrl.isEmpty) return;
          context.push('/detail',
              extra: DetailArgs(contentUrl: t.contentUrl, provider: t.provider));
        },
      ),
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.movie_rounded,
            color: AppColors.textHint, size: 22),
      );
}
