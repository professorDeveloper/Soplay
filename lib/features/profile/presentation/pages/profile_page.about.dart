// ignore_for_file: unused_element
part of 'profile_page.dart';

/// About: build, developer, server status and the support sheet.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  /// Resolved once. Rebuilt per build() it dropped the version row back to "…"
  /// on every rebuild of the list.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showDeveloper(BuildContext context) {
    showAdaptiveModal<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  'https://avatars.githubusercontent.com/u/108933534?v=4',
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 56,
                    height: 56,
                    color: AppColors.primary,
                    child: const Center(
                      child: Text(
                        'AX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Azamov X',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'profile.developer_role'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _open('https://t.me/ackles'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.telegram,
                            color: Color(0xFF2AABEE),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '@ackles',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.open_in_new_rounded,
                            color: AppColors.textHint,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_about'.tr()),
          _SectionCard(
          children: [
          _Tile(
          icon: Icons.info_outline_rounded,
          title: 'Sozo',
          trailing: FutureBuilder<PackageInfo>(
          future: _packageInfo,
          builder: (_, snap) => Text(
          snap.hasData
          ? 'v${snap.data!.version} (${snap.data!.buildNumber})'
          : '…',
          style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 13,
          ),
          ),
          ),
          onTap: null,
          ),
          const _TileDivider(),
          _Tile(
          icon: Icons.person_outline_rounded,
          title: 'profile.developer'.tr(),
          trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          Text(
          'Azamov X',
          style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          ),
          ),
          SizedBox(width: 4),
          _TileChevron(),
          ],
          ),
          onTap: () => _showDeveloper(context),
          ),
          const _TileDivider(),
          const _ServerCountdownTile(),
          ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SocialIcon(
                icon: Icons.telegram,
                label: 'Telegram',
                onTap: () => _open('https://t.me/sozoApp'),
              ),
              const SizedBox(width: 16),
              _SocialIcon(
                icon: Icons.language_rounded,
                label: 'profile.website'.tr(),
                onTap: () => _open('https://sozo.azamov.me'),
              ),
              const SizedBox(width: 16),
              _SocialIcon(
                icon: Icons.code_rounded,
                label: 'GitHub',
                onTap: () => _open('https://github.com/professorDeveloper'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerCountdownTile extends StatefulWidget {
  const _ServerCountdownTile();

  @override
  State<_ServerCountdownTile> createState() => _ServerCountdownTileState();
}

class _ServerCountdownTileState extends State<_ServerCountdownTile> {
  static final DateTime _deadline = DateTime.utc(2026, 10, 1);
  late final Timer _timer;
  final _remaining = ValueNotifier<Duration>(Duration.zero);

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  void _updateRemaining() {
    final diff = _deadline.difference(DateTime.now().toUtc());
    _remaining.value = diff.isNegative ? Duration.zero : diff;
  }

  @override
  void dispose() {
    _timer.cancel();
    _remaining.dispose();
    super.dispose();
  }

  void _showSupportSheet(BuildContext context) {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServerSupportSheet(remaining: _remaining),
    );
  }

  static String _fmt(Duration rem) {
    final d = rem.inDays;
    final h = rem.inHours.remainder(24);
    final m = rem.inMinutes.remainder(60);
    final s = rem.inSeconds.remainder(60);
    if (d > 0) return '${d}d ${h}h ${m}m';
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return _Tile(
      icon: Icons.dns_outlined,
      title: 'profile.server'.tr(),
      onTap: () => _showSupportSheet(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ValueListenableBuilder<Duration>(
              valueListenable: _remaining,
              builder: (_, rem, _) {
                return Text(
                  rem == Duration.zero ? 'profile.expired'.tr() : _fmt(rem),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // "Expired" means the server is down and nothing will load.
                    // That is an error, not a place to show the theme.
                    color: rem == Duration.zero
                        ? AppColors.error
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          const _TileChevron(),
        ],
      ),
    );
  }
}

class _ServerSupportSheet extends StatelessWidget {
  const _ServerSupportSheet({required this.remaining});

  final ValueNotifier<Duration> remaining;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dns_rounded,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'profile.support_title'.tr(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration>(
            valueListenable: remaining,
            builder: (_, rem, _) {
              final expired = rem == Duration.zero;
              if (expired) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    // Same reasoning as the countdown row above it.
                    'profile.server_expired'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }
              final d = rem.inDays;
              final h = rem.inHours.remainder(24);
              final m = rem.inMinutes.remainder(60);
              final s = rem.inSeconds.remainder(60);
              return Row(
                children: [
                  _SheetCountdownCell(value: d, label: 'profile.days'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: h, label: 'profile.hours'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: m, label: 'profile.min'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: s, label: 'profile.sec'.tr()),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration>(
            valueListenable: remaining,
            builder: (_, rem, _) {
              final expired = rem == Duration.zero;
              return Text(
                expired
                    ? 'profile.support_body_expired'.tr()
                    : 'profile.support_body'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(
                  Uri.parse('https://t.me/ackles'),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.favorite_rounded, size: 18),
              label: Text('profile.support_developer'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetCountdownCell extends StatelessWidget {
  const _SheetCountdownCell({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The installable-extension entries, in one card instead of four free-standing
/// ones. Which of them exist depends on the platform, so the card builds itself
/// out of whatever is supported and disappears entirely when nothing is.
