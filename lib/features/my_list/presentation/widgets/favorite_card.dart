import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';

class FavoriteCard extends StatelessWidget {
  const FavoriteCard({
    super.key,
    required this.item,
    required this.onTap,
    this.synced = false,
  });

  final FavoriteEntity item;
  final VoidCallback onTap;

  /// Whether this favorite is saved to the user's account (vs local-only).
  final bool synced;

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isEmpty ? 'Untitled' : item.title.trim();
    final description = item.description.trim();
    final meta = description.isNotEmpty ? description : item.provider.trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HomeNetworkImage(
                    url: item.thumbnail,
                    borderRadius: BorderRadius.zero,
                    placeholderIcon: Icons.movie_outlined,
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xB0000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.bookmark_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Tooltip(
                      message: (synced
                              ? 'my_list.saved_account'
                              : 'my_list.saved_local')
                          .tr(),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          synced
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          color: synced
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.8),
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.18,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
