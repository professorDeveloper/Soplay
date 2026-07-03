import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/system/system_controls.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';

class ReaderPage extends StatefulWidget {
  final ReaderArgs args;
  const ReaderPage({super.key, required this.args});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const Color _accent = Color(0xFF5B8DEF);

  final _hive = getIt<HiveService>();
  final _downloads = getIt<DownloadService>();

  late int _chapterIndex;
  List<MangaPageEntity> _pages = const [];
  Map<String, String> _headers = const {};
  bool _loading = true;
  bool _localChapter = false;
  String? _error;

  // 'vertical' (continuous webtoon) | 'horizontal' (paged)
  late String _mode;
  late bool _rtl;
  late String _bgPref; // 'black' | 'gray' | 'white'
  double _brightness = 0.5;

  Color get _backgroundColor => switch (_bgPref) {
        'white' => const Color(0xFFFAFAFA),
        'gray' => const Color(0xFF2A2A2A),
        _ => const Color(0xFF0A0A0A),
      };

  // Current page is a ValueNotifier so scrolling/paging only rebuilds the tiny
  // page indicator + slider — NOT the whole reader (that was the main-thread jank).
  final ValueNotifier<int> _page = ValueNotifier<int>(0);
  // In-progress seekbar drag target (null when not scrubbing). While dragging we
  // only move the thumb + counter; the content jumps once on release — jumping a
  // huge webtoon on every slider tick was the lag.
  final ValueNotifier<int?> _dragging = ValueNotifier<int?>(null);
  bool _showOverlay = true;

  PageController? _pageController;
  // Vertical (webtoon) mode uses a positioned list so the current page can be
  // read from the actually-rendered item positions (accurate with variable
  // image heights + fast scroll), and seeking jumps to an exact page index.
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  int _initialIndex = 0;
  Timer? _saveDebounce;

  int get _currentPage => _page.value;
  int get _pageCount => _pages.length;
  List<dynamic> get _chapters => widget.args.chapters;

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.args.initialChapterIndex
        .clamp(0, widget.args.chapters.length - 1);
    _mode = _hive.getReaderMode(widget.args.contentUrl);
    _rtl = _hive.getReaderRtl(widget.args.contentUrl);
    _bgPref = _hive.getReaderBackground();
    _itemPositionsListener.itemPositions.addListener(_onItemPositions);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setWakelock(true);
    SystemControls.getBrightness().then((v) {
      if (mounted) setState(() => _brightness = v);
    });
    _loadChapter(_chapterIndex, startPage: widget.args.resumePage);
  }

  @override
  void dispose() {
    _saveProgress(); // flush final position
    _saveDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onItemPositions);
    _pageController?.dispose();
    _page.dispose();
    _dragging.dispose();
    _setWakelock(false);
    SystemControls.resetBrightness();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _setWakelock(bool on) {
    try {
      WakelockPlus.toggle(enable: on);
    } catch (_) {}
  }

  Future<void> _loadChapter(int index, {int startPage = 0}) async {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _loading = true;
      _error = null;
      _pages = const [];
    });
    _page.value = 0;
    final ch = widget.args.chapters[index];
    final ref = ch.mediaRef;

    // Prefer an already-downloaded copy of this chapter (offline first).
    final localId = DownloadService.mangaChapterId(
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      chapterRef: ref,
    );
    final local = await _downloads.localMangaPages(localId);
    if (!mounted) return;
    if (local.isNotEmpty) {
      final start = startPage.clamp(0, local.length - 1);
      _pageController?.dispose();
      _pageController = PageController(initialPage: start);
      _page.value = start;
      _initialIndex = start;
      setState(() {
        _localChapter = true;
        _pages = local;
        _headers = const {};
        _loading = false;
      });
      _scheduleSave();
      return;
    }
    _localChapter = false;

    final result = await getIt<GetPagesUseCase>()(
      ref: ref,
      provider: widget.args.provider,
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        final start = value.pages.isEmpty
            ? 0
            : startPage.clamp(0, value.pages.length - 1);
        _pageController?.dispose();
        _pageController = PageController(initialPage: start);
        _page.value = start;
        _initialIndex = start;
        setState(() {
          _pages = value.pages;
          _headers = value.headers;
          _loading = false;
        });
        _scheduleSave();
      case Failure(:final error):
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  // ---- progress / page tracking ----

  // The current page is the list item occupying the top of the viewport — read
  // directly from the actually-rendered item positions. This is accurate with
  // variable webtoon image heights and fast scrolling (a scroll-fraction
  // estimate is not, which made the seekbar/counter jump around).
  void _onItemPositions() {
    if (_mode != 'vertical' || _pageCount == 0) return;
    final positions = _itemPositionsListener.itemPositions.value
        .where((p) => p.index < _pageCount && p.itemTrailingEdge > 0);
    if (positions.isEmpty) return;
    // Prefer the page straddling the top edge (leadingEdge <= 0); else the first
    // visible page.
    final straddling = positions.where((p) => p.itemLeadingEdge <= 0);
    final page = (straddling.isNotEmpty
            ? straddling.reduce(
                (a, b) => a.itemLeadingEdge >= b.itemLeadingEdge ? a : b)
            : positions.reduce(
                (a, b) => a.itemLeadingEdge <= b.itemLeadingEdge ? a : b))
        .index;
    if (page != _page.value) {
      _page.value = page; // notifier only — slider + counter rebuild, not the list
      _scheduleSave();
    }
  }

  void _jumpVerticalTo(int page) {
    if (!_itemScrollController.isAttached || _pageCount == 0) return;
    _itemScrollController.jumpTo(index: page.clamp(0, _pageCount - 1));
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _saveProgress);
  }

  void _saveProgress() {
    if (_pageCount == 0) return;
    final ch = widget.args.chapters[_chapterIndex];
    getIt<HistoryService>().save(HistoryItem(
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      title: widget.args.title,
      thumbnail: widget.args.thumbnail,
      isSerial: true,
      episodeIndex: _chapterIndex,
      episodeNumber: ch.episode,
      episodeLabel: ch.label,
      positionMs: _currentPage,
      durationMs: _pageCount > 1 ? _pageCount - 1 : 0,
      watchedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ---- navigation ----

  void _toggleOverlay() => setState(() => _showOverlay = !_showOverlay);

  void _goToPage(int page) {
    final clamped = page.clamp(0, _pageCount - 1);
    if (_mode == 'horizontal') {
      _pageController?.animateToPage(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _jumpVerticalTo(clamped);
    }
    _page.value = clamped;
  }

  void _goNextPage() =>
      _currentPage < _pageCount - 1 ? _goToPage(_currentPage + 1) : _nextChapter();

  void _goPrevPage() =>
      _currentPage > 0 ? _goToPage(_currentPage - 1) : _prevChapter();

  void _nextChapter() {
    if (_chapterIndex < _chapters.length - 1) {
      _loadChapter(_chapterIndex + 1);
    } else {
      _snack('manga.last_chapter'.tr());
    }
  }

  void _prevChapter() {
    if (_chapterIndex > 0) {
      _loadChapter(_chapterIndex - 1);
    } else {
      _snack('manga.first_chapter'.tr());
    }
  }

  void _setMode(String mode) {
    if (mode == _mode) return;
    final page = _currentPage;
    _hive.saveReaderMode(widget.args.contentUrl, mode);
    if (mode == 'horizontal') {
      _pageController?.dispose();
      _pageController = PageController(initialPage: page);
    } else {
      // The freshly-built vertical list starts at the current page.
      _initialIndex = page;
    }
    setState(() => _mode = mode);
  }

  void _toggleRtl() {
    final next = !_rtl;
    _hive.saveReaderRtl(widget.args.contentUrl, next);
    setState(() => _rtl = next);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  void _handleTapZone(TapUpDetails d) {
    // In continuous (webtoon) mode scrolling is the navigation, so any tap just
    // toggles the overlay. Side tap-zones only make sense in paged mode.
    if (_mode == 'vertical') {
      _toggleOverlay();
      return;
    }
    final w = MediaQuery.sizeOf(context).width;
    final x = d.localPosition.dx;
    if (x < w * 0.3) {
      _rtl ? _goNextPage() : _goPrevPage();
    } else if (x > w * 0.7) {
      _rtl ? _goPrevPage() : _goNextPage();
    } else {
      _toggleOverlay();
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(child: _content()),
          if (_showOverlay) _topBar(),
          if (_showOverlay && !_loading && _error == null) _bottomBar(),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white38, size: 44),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () =>
                    _loadChapter(_chapterIndex, startPage: _currentPage),
                child: Text('general.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    if (_pages.isEmpty) {
      return Center(
        child: Text('manga.no_pages'.tr(),
            style: const TextStyle(color: Colors.white54)),
      );
    }
    return _mode == 'horizontal' ? _horizontalReader() : _verticalReader();
  }

  Widget _verticalReader() {
    return GestureDetector(
      onTapUp: _handleTapZone,
      child: ScrollablePositionedList.builder(
        // Fresh list per chapter so initialScrollIndex (the resume page) applies.
        key: ValueKey('v_$_chapterIndex'),
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        initialScrollIndex: _initialIndex.clamp(0, _pageCount),
        // Render a screen ahead so the next strip is decoded before it scrolls in.
        minCacheExtent: 2000,
        itemCount: _pages.length + 1,
        itemBuilder: (context, i) {
          if (i == _pages.length) return _chapterFooter();
          return _PageImage(
            key: ValueKey('v_${_chapterIndex}_$i'),
            page: _pages[i],
            headers: _headers,
            zoomable: false,
          );
        },
      ),
    );
  }

  Widget _horizontalReader() {
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          reverse: _rtl,
          itemCount: _pages.length,
          onPageChanged: (i) {
            _page.value = i; // notifier only — no setState
            _scheduleSave();
          },
          itemBuilder: (context, i) => Center(
            child: _PageImage(
              key: ValueKey('h_${_chapterIndex}_$i'),
              page: _pages[i],
              headers: _headers,
              zoomable: true,
            ),
          ),
        ),
        // Translucent tap layer so PageView still gets horizontal drags and
        // InteractiveViewer still gets pinch gestures.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _handleTapZone,
          ),
        ),
      ],
    );
  }

  Widget _chapterFooter() {
    final hasNext = _chapterIndex < _chapters.length - 1;
    final nextLabel =
        hasNext ? widget.args.chapters[_chapterIndex + 1].label : null;
    final onWhite = _bgPref == 'white';
    final muted = onWhite ? Colors.black54 : Colors.white54;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 60),
      child: Column(
        children: [
          Icon(
            hasNext ? Icons.check_circle_outline : Icons.done_all_rounded,
            color: onWhite ? Colors.black26 : Colors.white30,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            hasNext ? 'manga.chapter_ended'.tr() : 'manga.last_chapter'.tr(),
            style: TextStyle(color: muted, fontSize: 13),
          ),
          if (hasNext) ...[
            const SizedBox(height: 20),
            Material(
              color: _accent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _nextChapter,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 230),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'manga.next_chapter'.tr().toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            if (nextLabel != null && nextLabel.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  nextLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _topBar() {
    final ch = widget.args.chapters[_chapterIndex];
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 4,
          bottom: 8,
          left: 4,
          right: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.args.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(ch.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11.5)),
                ],
              ),
            ),
            _downloadButton(ch),
            IconButton(
              tooltip: 'manga.chapters'.tr(),
              icon: const Icon(Icons.format_list_bulleted, color: Colors.white),
              onPressed: _openChapterList,
            ),
            IconButton(
              tooltip: 'general.settings'.tr(),
              icon: const Icon(Icons.tune, color: Colors.white),
              onPressed: _openSettingsSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadButton(EpisodeEntity ch) {
    final id = DownloadService.mangaChapterId(
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      chapterRef: ch.mediaRef,
    );
    return ValueListenableBuilder<int>(
      valueListenable: _downloads.revision,
      builder: (context, _, _) {
        final item = _downloads.get(id);
        final status = item?.status;
        if (status == DownloadStatus.downloading) {
          return SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: item != null && item.totalBytes > 0
                      ? item.progress
                      : null,
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }
        final done = _localChapter || status == DownloadStatus.completed;
        return IconButton(
          icon: Icon(
            done ? Icons.download_done_rounded : Icons.download_outlined,
            color: Colors.white,
          ),
          onPressed: done ? null : _downloadCurrentChapter,
        );
      },
    );
  }

  Future<void> _downloadCurrentChapter() async {
    if (_pages.isEmpty) return;
    final ch = widget.args.chapters[_chapterIndex];
    final item = DownloadItem(
      id: DownloadService.mangaChapterId(
        contentUrl: widget.args.contentUrl,
        provider: widget.args.provider,
        chapterRef: ch.mediaRef,
      ),
      kind: 'manga',
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      title: widget.args.title,
      thumbnail: widget.args.thumbnail,
      videoUrl: '',
      localPath: '',
      headers: _headers,
      pageUrls: _pages.map((p) => p.imageUrl).toList(),
      chapterRef: ch.mediaRef,
      chapterIndex: _chapterIndex,
      isSerial: true,
      episodeNumber: ch.episode,
      episodeLabel: ch.label,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _downloads.startDownload(item);
    if (!mounted) return;
    _snack('manga.download_started'.tr());
  }

  // ---- sheets ----

  void _openChapterList() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (context, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('manga.chapters'.tr(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: _chapters.length,
                itemBuilder: (context, i) {
                  final ch = widget.args.chapters[i];
                  final selected = i == _chapterIndex;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: _accent.withValues(alpha: 0.12),
                    leading: Icon(
                      selected ? Icons.play_arrow_rounded : Icons.menu_book_outlined,
                      color: selected ? _accent : Colors.white38,
                      size: 20,
                    ),
                    title: Text(ch.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: selected ? _accent : Colors.white,
                            fontSize: 13.5)),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (i != _chapterIndex) _loadChapter(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettingsSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('manga.reading_mode'.tr(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              _segmented(
                options: {
                  'vertical': 'manga.mode_continuous'.tr(),
                  'horizontal': 'manga.mode_paged'.tr(),
                },
                value: _mode,
                onChanged: (v) {
                  _setMode(v);
                  setSheet(() {});
                },
              ),
              if (_mode == 'horizontal') ...[
                const SizedBox(height: 18),
                Text('manga.direction'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                _segmented(
                  options: {
                    'ltr': 'manga.dir_ltr'.tr(),
                    'rtl': 'manga.dir_rtl'.tr(),
                  },
                  value: _rtl ? 'rtl' : 'ltr',
                  onChanged: (v) {
                    final wantRtl = v == 'rtl';
                    if (wantRtl != _rtl) _toggleRtl();
                    setSheet(() {});
                  },
                ),
              ],
              const SizedBox(height: 18),
              Text('manga.background'.tr(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              _segmented(
                options: {
                  'black': 'manga.bg_black'.tr(),
                  'gray': 'manga.bg_gray'.tr(),
                  'white': 'manga.bg_white'.tr(),
                },
                value: _bgPref,
                onChanged: (v) {
                  _hive.saveReaderBackground(v);
                  setState(() => _bgPref = v);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.brightness_6_outlined,
                      color: Colors.white54, size: 18),
                  Expanded(
                    child: Slider(
                      activeColor: _accent,
                      inactiveColor: Colors.white24,
                      min: 0.05,
                      max: 1.0,
                      value: _brightness.clamp(0.05, 1.0),
                      onChanged: (v) {
                        setSheet(() => _brightness = v);
                        setState(() => _brightness = v);
                        SystemControls.setBrightness(v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmented({
    required Map<String, String> options,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: options.entries.map((e) {
          final selected = e.key == value;
          return Expanded(
            child: HoverTap(
              onTap: () => onChanged(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  e.value,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _bottomBar() {
    final hasPrevChapter = _chapterIndex > 0;
    final hasNextChapter = _chapterIndex < _chapters.length - 1;
    final maxPage = (_pageCount - 1).clamp(0, 9999).toDouble();
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 8,
          top: 10,
          left: 8,
          right: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.skip_previous_rounded,
                  color: hasPrevChapter ? Colors.white : Colors.white24),
              onPressed: hasPrevChapter ? _prevChapter : null,
            ),
            Expanded(
              // Only this rebuilds as pages change / while scrubbing.
              child: ValueListenableBuilder<int?>(
                valueListenable: _dragging,
                builder: (context, drag, _) => ValueListenableBuilder<int>(
                  valueListenable: _page,
                  builder: (context, page, _) {
                    final display = (drag ?? page).clamp(0, maxPage.toInt());
                    return Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.5,
                              activeTrackColor: _accent,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: _accent,
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14),
                            ),
                            child: Slider(
                              min: 0,
                              max: maxPage,
                              value: display.toDouble(),
                              // Live: move thumb + counter only (cheap). The
                              // content jumps once on release.
                              onChanged: _pageCount > 1
                                  ? (v) => _dragging.value = v.round()
                                  : null,
                              onChangeEnd: (v) {
                                final target = v.round();
                                _dragging.value = null;
                                _goToPage(target);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${display + 1}/$_pageCount',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.skip_next_rounded,
                  color: hasNextChapter ? Colors.white : Colors.white24),
              onPressed: hasNextChapter ? _nextChapter : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single page image. Decoded at screen width (`memCacheWidth`) so huge
/// webtoon strips don't blow up memory or jank the main thread, with tap-to-retry
/// on failure. Kept as its own widget so each image rebuilds independently.
class _PageImage extends StatefulWidget {
  const _PageImage({
    super.key,
    required this.page,
    required this.headers,
    required this.zoomable,
  });

  final MangaPageEntity page;
  final Map<String, String> headers;
  final bool zoomable;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  static const Color _accent = Color(0xFF5B8DEF);
  int _retry = 0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (width * dpr).round();

    final url = widget.page.imageUrl;
    final isLocal = !url.startsWith('http');

    final Widget img = isLocal
        ? Image.file(
            File(url),
            key: ValueKey('$url#$_retry'),
            fit: BoxFit.fitWidth,
            width: width,
            cacheWidth: cacheW,
            errorBuilder: (_, _, _) => _errorTile(width),
          )
        : CachedNetworkImage(
            key: ValueKey('$url#$_retry'),
            imageUrl: url,
            httpHeaders: widget.headers,
            fit: BoxFit.fitWidth,
            width: width,
            // Downscale to the screen's pixel width — the key perf fix for tall strips.
            memCacheWidth: cacheW,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, _) => Container(
              width: width,
              height: width * 1.4,
              color: Colors.white.withValues(alpha: 0.02),
              child: const Center(
                child:
                    CircularProgressIndicator(color: _accent, strokeWidth: 1.8),
              ),
            ),
            errorWidget: (_, _, _) => _errorTile(width),
          );

    if (!widget.zoomable) return img;
    return InteractiveViewer(
      maxScale: 4,
      child: SizedBox(width: width, child: img),
    );
  }

  Widget _errorTile(double width) => HoverTap(
        onTap: () async {
          await CachedNetworkImage.evictFromCache(widget.page.imageUrl);
          if (mounted) setState(() => _retry++);
        },
        child: Container(
          width: width,
          height: 220,
          color: Colors.white.withValues(alpha: 0.03),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.refresh_rounded, color: Colors.white38, size: 30),
              const SizedBox(height: 8),
              Text('manga.tap_to_reload'.tr(),
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      );
}
