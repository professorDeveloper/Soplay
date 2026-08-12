import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riasdxd/core/di/injection.dart';
import 'package:riasdxd/core/system/responsive.dart';
import 'package:riasdxd/core/theme/app_colors.dart';
import 'package:riasdxd/features/notifications/data/services/release_notifier.dart';

/// Lets the user opt in/out of the client-side "new content" local alerts.
/// The toggles are read by [ReleaseNotifier] on its next poll.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final ReleaseNotifier _notifier = getIt<ReleaseNotifier>();

  late bool _recent = _notifier.recentReleasesEnabled;
  late bool _trending = _notifier.topTrendingEnabled;

  Future<void> _setRecent(bool value) async {
    setState(() => _recent = value);
    await _notifier.setRecentReleasesEnabled(value);
  }

  Future<void> _setTrending(bool value) async {
    setState(() => _trending = value);
    await _notifier.setTopTrendingEnabled(value);
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/main'),
        ),
        title: Text(
          'notifications.settings_title'.tr(),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: MaxWidthBox(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _Card(
              child: Column(
                children: [
                  _Row(
                    icon: Icons.fiber_new_rounded,
                    title: 'notifications.settings_recent_title'.tr(),
                    subtitle: 'notifications.settings_recent_subtitle'.tr(),
                    trailing: Switch.adaptive(
                      value: _recent,
                      activeThumbColor: AppColors.primary,
                      onChanged: _setRecent,
                    ),
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  _Row(
                    icon: Icons.local_fire_department_rounded,
                    title: 'notifications.settings_trending_title'.tr(),
                    subtitle: 'notifications.settings_trending_subtitle'.tr(),
                    trailing: Switch.adaptive(
                      value: _trending,
                      activeThumbColor: AppColors.primary,
                      onChanged: _setTrending,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'notifications.settings_hint'.tr(),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

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
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
