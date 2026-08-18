import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// External accounts this app can write to.
///
/// One screen even though there is currently one service: the connection has
/// consequences the user needs stated in one place — what gets written, and
/// how to stop it — and those do not belong scattered through Settings.
class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final AnilistService _anilist = getIt<AnilistService>();
  final AnilistLinkStore _links = getIt<AnilistLinkStore>();

  @override
  void initState() {
    super.initState();
    _anilist.addListener(_onChange);
  }

  @override
  void dispose() {
    _anilist.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    final error = _anilist.consumeError();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _connect() async {
    // Connecting stores the token against the Sozo account, so there has to be
    // one. Said plainly here rather than letting the backend answer 401 after
    // the user has already been bounced through a browser.
    if (!getIt<HiveService>().isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('anilist.sign_in_first'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final opened = await _anilist.beginLink();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('anilist.browser_failed'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'anilist.disconnect'.tr(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
        ),
        content: Text(
          'anilist.disconnect_confirm'.tr(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'anilist.disconnect'.tr(),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _anilist.disconnect();
    // The title-to-media map describes THIS account's shows; keeping it after a
    // disconnect would silently reattach them if a different AniList account
    // were connected next.
    await _links.clear();
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _anilist.viewer;
    final connected = _anilist.isConnected;
    final linkCount = _links.all().length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          'anilist.connections_title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: connected
                    ? kAnilistBlue.withValues(alpha: 0.35)
                    : AppColors.border,
                width: connected ? 1 : 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(url: viewer?.avatarUrl, connected: connected),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AniList',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            connected && viewer != null && viewer.name.isNotEmpty
                                ? viewer.name
                                : 'anilist.not_connected'.tr(),
                            style: TextStyle(
                              color: connected
                                  ? kAnilistBlue
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_anilist.linking)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kAnilistBlue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  connected
                      ? 'anilist.connected_explainer'.tr()
                      : 'anilist.connect_explainer'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: connected
                      ? OutlinedButton.icon(
                          onPressed: _disconnect,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          icon: const Icon(Icons.link_off_rounded, size: 18),
                          label: Text('anilist.disconnect'.tr()),
                        )
                      : FilledButton.icon(
                          onPressed: _anilist.linking ? null : _connect,
                          style: FilledButton.styleFrom(
                            backgroundColor: kAnilistBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(
                            'anilist.connect'.tr(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (connected) ...[
            const SizedBox(height: 12),
            _Row(
              icon: Icons.auto_awesome_motion_rounded,
              title: 'anilist.open_library'.tr(),
              onTap: () => context.push('/anilist'),
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.link_rounded,
              title: 'anilist.linked_titles'.tr(),
              subtitle: linkCount > 0
                  ? 'anilist.linked_titles_count'.tr(args: ['$linkCount'])
                  : 'anilist.linked_titles_none'.tr(),
              onTap: linkCount == 0
                  ? null
                  : () async {
                      await context.push('/anilist/links');
                      if (mounted) setState(() {});
                    },
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'anilist.privacy_note'.tr(),
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.connected});

  final String? url;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: connected
            ? null
            : const LinearGradient(colors: [kAnilistBlue, kAnilistBlueDeep]),
        color: connected ? AppColors.surfaceVariant : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: (connected && url != null && url!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const Icon(
                Icons.person_rounded,
                color: AppColors.textHint,
              ),
            )
          : const Center(child: AnilistLogo(size: 30)),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon,
                  color: enabled ? kAnilistBlue : AppColors.textHint, size: 21),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
