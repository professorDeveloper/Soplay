import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';

/// The local titles tied to an AniList entry, and a way to break a wrong tie.
///
/// This screen exists because automatic matching can be wrong. When it is, the
/// user needs to SEE that a link was made on their behalf and be able to undo
/// it — otherwise a bad guess keeps writing episodes into the wrong show with
/// no visible cause.
class AnilistLinksPage extends StatefulWidget {
  const AnilistLinksPage({super.key});

  @override
  State<AnilistLinksPage> createState() => _AnilistLinksPageState();
}

class _AnilistLinksPageState extends State<AnilistLinksPage> {
  final AnilistLinkStore _store = getIt<AnilistLinkStore>();
  late List<AnilistLink> _items = _store.all();

  Future<void> _unlink(AnilistLink link) async {
    await _store.remove(link.provider, link.contentUrl);
    if (!mounted) return;
    setState(() => _items = _store.all());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('anilist.unlinked'.tr(args: [link.title])),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
        title: Text(
          'anilist.linked_titles'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: _items.isEmpty
          ? Center(
              child: AnilistStateMessage(
                icon: Icons.link_off_rounded,
                text: 'anilist.linked_titles_none'.tr(),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _LinkTile(
                link: _items[i],
                onUnlink: () => _unlink(_items[i]),
              ),
            ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link, required this.onUnlink});

  final AnilistLink link;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnilistCover(url: link.coverImage, width: 46, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AnilistChip(
                      label: link.provider.isEmpty ? '—' : link.provider,
                      color: AppColors.textSecondary,
                    ),
                    if (link.auto)
                      AnilistChip(
                        label: 'anilist.auto_matched'.tr(),
                        icon: Icons.auto_fix_high_rounded,
                        color: AppColors.rating,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'anilist.unlink'.tr(),
            onPressed: onUnlink,
            icon: const Icon(Icons.link_off_rounded,
                color: AppColors.textHint, size: 20),
          ),
        ],
      ),
    );
  }
}
