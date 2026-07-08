import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final DownloadService _service = getIt<DownloadService>();
  List<DownloadItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _items = _service.getAll());
  }

  void _clearAll() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'downloads.delete_all_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _service.clearAll();
            },
            child: Text(
              'general.delete'.tr(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _play(DownloadItem item) {
    if (item.status != DownloadStatus.completed) return;

    if (item.isManga) {
      final group =
          _items
              .where(
                (d) =>
                    d.isManga &&
                    d.status == DownloadStatus.completed &&
                    d.contentUrl == item.contentUrl,
              )
              .toList()
            ..sort(
              (a, b) => (a.chapterIndex ?? 0).compareTo(b.chapterIndex ?? 0),
            );
      final chapters = group
          .map(
            (d) => EpisodeEntity(
              episode: d.episodeNumber ?? 0,
              label: d.episodeLabel ?? d.title,
              mediaRef: d.chapterRef ?? '',
            ),
          )
          .toList();
      var start = group.indexWhere((d) => d.id == item.id);
      if (start < 0) start = 0;
      context.push(
        '/reader',
        extra: ReaderArgs(
          title: item.title,
          provider: item.provider,
          contentUrl: item.contentUrl,
          thumbnail: item.displayThumbnail,
          chapters: chapters,
          initialChapterIndex: start,
        ),
      );
      return;
    }

    final file = File(item.localPath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('downloads.file_not_found'.tr())));
      return;
    }
    context.push(
      '/player',
      extra: PlayerArgs(
        title: item.isSerial && item.episodeNumber != null
            ? '${item.title} · EP ${item.episodeNumber}'
            : item.title,
        provider: item.provider,
        headers: const {},
        contentUrl: item.contentUrl,
        thumbnail: item.displayThumbnail,
        movieUrl: item.localPath.endsWith('.m3u8')
            ? Uri.file(item.localPath).toString()
            : item.localPath,
        type: item.localPath.endsWith('.m3u8') ? 'hls' : null,
        showDownloadAction: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPad + 8)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (context.canPop()) context.pop();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'navigation.downloads'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_items.isNotEmpty)
                    GestureDetector(
                      onTap: _clearAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'downloads.clear_all'.tr(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (_items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else
            SliverList.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(
                color: AppColors.divider,
                height: 1,
                indent: 82,
              ),
              itemBuilder: (_, i) => _DownloadRow(
                item: _items[i],
                onTap: () => _play(_items[i]),
                onRemove: () => _service.remove(_items[i].id),
                onRetry: () => _service.startDownload(_items[i]),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomPad + 24)),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.item,
    required this.onTap,
    required this.onRemove,
    required this.onRetry,
  });

  final DownloadItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
        onTap: item.status == DownloadStatus.completed ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 54,
                  height: 76,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HomeNetworkImage(
                        url: item.displayThumbnail,
                        borderRadius: BorderRadius.zero,
                        placeholderIcon: item.isManga
                            ? Icons.menu_book_outlined
                            : Icons.movie_outlined,
                      ),
                      if (item.status == DownloadStatus.completed)
                        Positioned.fill(
                          child: ColoredBox(
                            color: const Color(0x44000000),
                            child: Icon(
                              item.isManga
                                  ? Icons.menu_book_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    if (item.isSerial && item.episodeNumber != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'EP ${item.episodeNumber}${item.episodeLabel != null ? ' · ${item.episodeLabel}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    if (item.status == DownloadStatus.downloading) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 3,
                          backgroundColor: AppColors.divider,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.isManga
                            ? 'manga.downloaded_pages'.tr(args: [
                                '${item.downloadedBytes}',
                                '${item.totalBytes}',
                              ])
                            : _isHls(item.videoUrl)
                            ? 'downloads.segments_progress'.tr(args: [
                                '${item.downloadedBytes}',
                                '${item.totalBytes}',
                              ])
                            : item.totalBytes > 0
                            ? '${_mb(item.downloadedBytes)} / ${_mb(item.totalBytes)}'
                            : 'downloads.downloaded_amount'
                                .tr(args: [_mb(item.downloadedBytes)]),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 10,
                        ),
                      ),
                    ] else if (item.status == DownloadStatus.completed)
                      Text(
                        item.isManga
                            ? 'downloads.pages_count'
                                .tr(args: ['${item.totalBytes}'])
                            : item.totalBytes > 0
                            ? _mb(item.totalBytes)
                            : 'downloads.downloaded'.tr(),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (item.status == DownloadStatus.failed)
                      Text(
                        'downloads.failed'.tr(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        'downloads.pending'.tr(),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (item.status == DownloadStatus.failed)
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                )
              else if (item.status == DownloadStatus.completed)
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      );

    if (isDesktopPlatform) {
      return Row(
        children: [
          Expanded(child: row),
          IconButton(
            tooltip: 'downloads.remove'.tr(),
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.textHint),
            onPressed: onRemove,
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.primary.withValues(alpha: 0.15),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.primary,
          size: 22,
        ),
      ),
      child: row,
    );
  }

  bool _isHls(String url) => url.toLowerCase().contains('.m3u8');

  String _mb(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download_rounded,
              color: AppColors.textHint, size: 52),
          const SizedBox(height: 14),
          Text(
            'downloads.empty_title'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'downloads.empty_subtitle'.tr(),
            style: const TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
