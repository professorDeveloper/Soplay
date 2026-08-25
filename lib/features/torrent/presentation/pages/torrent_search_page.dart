import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/features/detail/domain/entities/player_args.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/torrent/torrent_engine.dart';
import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/torrent_search_repository.dart';
import 'package:soplay/features/torrent/data/torrent_trackers.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';
import 'package:soplay/features/torrent/presentation/torrent_playback.dart';
import 'package:soplay/features/torrent/presentation/torrent_search_controller.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_filter_sheet.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_result_tile.dart';

/// Search Nyaa, Tokyo Toshokan and nekoBT at once, and stream what comes back.
///
/// The page deliberately does not try to look like the rest of the app's
/// browse surfaces. There are no posters here because torrents have none — a
/// release is a *file name*, and pretending otherwise would mean inventing
/// artwork and burying the only things that matter: quality, size and whether
/// anyone is seeding it.
class TorrentSearchPage extends StatefulWidget {
  const TorrentSearchPage({
    super.key,
    this.initialQuery,
    this.onPicked,
  });

  /// Pre-filled search term. Set when arriving from a title's detail page.
  final String? initialQuery;

  /// When supplied, the page hands the prepared stream back instead of playing
  /// it itself. Lets a detail page use this as a source picker.
  final void Function(TorrentStreamHandle handle)? onPicked;

  @override
  State<TorrentSearchPage> createState() => _TorrentSearchPageState();
}

class _TorrentSearchPageState extends State<TorrentSearchPage> {
  final _textController = TextEditingController();
  final _repository = TorrentSearchRepository();
  final _engine = TorrentEngine();

  late final TorrentSearchController _controller =
      TorrentSearchController(repository: _repository);

  Set<String> _enabledIndexers = const {};

  @override
  void initState() {
    super.initState();
    _enabledIndexers = _controller.enabledIndexers;

    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _textController.text = initial;
      _controller
        ..onTermChanged(initial)
        ..search();
    }

    // Torrent pieces are cached to disk and a few nights of watching adds up
    // fast. Clearing on entry rather than on exit means a crash mid-episode
    // still gets cleaned up, and the user never pays for last week's viewing.
    _engine.clearCache();
  }

  @override
  void dispose() {
    _controller.dispose();
    _repository.dispose();
    _engine.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await TorrentFilterSheet.show(
      context,
      filters: _controller.filters,
      indexers: _controller.indexers,
      enabledIndexers: _enabledIndexers,
    );
    if (result == null) return;
    setState(() => _enabledIndexers = result.indexers);
    _controller
      ..setEnabledIndexers(result.indexers)
      ..setFilters(result.filters);
  }

  Future<void> _play(TorrentResult result) async {
    final handle = await TorrentPlayback.prepare(
      context,
      result,
      engine: _engine,
    );
    if (handle == null || !mounted) return;

    final onPicked = widget.onPicked;
    if (onPicked != null) {
      onPicked(handle);
      return;
    }

    // Straight into the app's own player. The URL is an ordinary local HTTP
    // stream by this point, so nothing in the player needs to know a torrent
    // is behind it — which is exactly why the engine hands back a URL rather
    // than a custom source.
    await context.push(
      '/player',
      extra: PlayerArgs(
        title: handle.title,
        provider: _torrentProvider,
        headers: const {},
        movieUrl: handle.url.toString(),
        // A torrent stream is not a resolvable catalogue item, so there is
        // nothing for the download action to re-fetch later.
        showDownloadAction: false,
      ),
    );

    // Playback is over (or the user backed out). Close the swarm connection:
    // leaving it open keeps the device uploading to strangers after the user
    // thinks they are done, which is the one thing this feature must not do.
    await _engine.drop(handle.hash);
  }

  /// Provider id carried into the player and history. Distinct from any real
  /// source id so a torrent entry can never be mistaken for one that can be
  /// re-resolved from a catalogue.
  static const _torrentProvider = 'torrent';

  /// Long-press menu.
  ///
  /// "Open in torrent app" is here because streaming is not always what the
  /// user wants — a season pack they intend to keep belongs in a real client
  /// like LibreTorrent, which seeds properly and survives the app being closed.
  /// Sending the magnet out with an ACTION_VIEW intent is all that takes, and
  /// it is what the torrenting guides recommend on Android anyway.
  Future<void> _showActions(TorrentResult result) async {
    final link = result.engineLink(
      extraTrackers: TorrentTrackers.forIndexer(result.indexerId),
    );
    if (link == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                result.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.content_copy_rounded, color: AppColors.textSecondary),
              title: Text(
                'torrent.copy_magnet'.tr(),
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            ListTile(
              leading: Icon(Icons.open_in_new_rounded, color: AppColors.textSecondary),
              title: Text(
                'torrent.open_external'.tr(),
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.of(context).pop('external'),
            ),
            if (result.pageUrl != null)
              ListTile(
                leading: Icon(Icons.public_rounded, color: AppColors.textSecondary),
                title: Text(
                  'torrent.open_page'.tr(),
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop('page'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('torrent.magnet_copied'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case 'external':
        // externalApplication so Android offers the installed torrent clients
        // rather than trying to render `magnet:` in a webview.
        await launchUrl(
          Uri.parse(link),
          mode: LaunchMode.externalApplication,
        );
      case 'page':
        final page = result.pageUrl;
        if (page != null) {
          await launchUrl(Uri.parse(page), mode: LaunchMode.externalApplication);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: _searchField(),
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'torrent.filters'.tr(),
            onPressed: _openFilters,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: _categoryBar(),
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _body(),
      ),
    );
  }

  Widget _searchField() => TextField(
        controller: _textController,
        autofocus: widget.initialQuery == null,
        textInputAction: TextInputAction.search,
        onChanged: _controller.onTermChanged,
        onSubmitted: (_) => _controller.search(),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'torrent.search_hint'.tr(),
          hintStyle: TextStyle(color: AppColors.textHint, fontSize: 15),
          border: InputBorder.none,
          isDense: true,
        ),
      );

  Widget _categoryBar() {
    const categories = [
      TorrentCategory.animeEnglish,
      TorrentCategory.anime,
      TorrentCategory.animeNonEnglish,
      TorrentCategory.animeRaw,
      TorrentCategory.liveAction,
      TorrentCategory.all,
    ];

    return SizedBox(
      height: 46,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final category in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: ChoiceChip(
                  label: Text(_categoryLabel(category)),
                  selected: _controller.query.category == category,
                  onSelected: (_) => _controller.setCategory(category),
                ),
              ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ActionChip(
                avatar: const Icon(Icons.swap_vert_rounded, size: 16),
                label: Text(_sortLabel(_controller.query.sort)),
                onPressed: _pickSort,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(TorrentCategory category) => switch (category) {
        TorrentCategory.all => 'torrent.cat_all'.tr(),
        TorrentCategory.anime => 'torrent.cat_anime'.tr(),
        TorrentCategory.animeEnglish => 'torrent.cat_english'.tr(),
        TorrentCategory.animeNonEnglish => 'torrent.cat_non_english'.tr(),
        TorrentCategory.animeRaw => 'torrent.cat_raw'.tr(),
        TorrentCategory.animeMusicVideo => 'torrent.cat_amv'.tr(),
        TorrentCategory.liveAction => 'torrent.cat_live_action'.tr(),
      };

  String _sortLabel(TorrentSort sort) => switch (sort) {
        TorrentSort.seeders => 'torrent.sort_seeders'.tr(),
        TorrentSort.date => 'torrent.sort_date'.tr(),
        TorrentSort.size => 'torrent.sort_size'.tr(),
        TorrentSort.downloads => 'torrent.sort_downloads'.tr(),
      };

  Future<void> _pickSort() async {
    final sort = await showModalBottomSheet<TorrentSort>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in TorrentSort.values)
              ListTile(
                title: Text(
                  _sortLabel(sort),
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                trailing: _controller.query.sort == sort
                    ? Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(sort),
              ),
          ],
        ),
      ),
    );
    if (sort != null) _controller.setSort(sort);
  }

  Widget _body() {
    if (_controller.loading && _controller.results.isEmpty) {
      return _centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'torrent.searching'.tr(),
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (!_controller.hasSearched) {
      return _message(
        icon: Icons.travel_explore_rounded,
        title: 'torrent.title'.tr(),
        body: 'torrent.empty_hint'.tr(),
      );
    }

    if (_controller.results.isEmpty) {
      return _message(
        icon: Icons.search_off_rounded,
        title: 'torrent.no_results'.tr(),
        body: 'torrent.no_results_hint'.tr(),
      );
    }

    return Column(
      children: [
        // A thin bar rather than a blocking spinner: results from the previous
        // query stay usable while a refined one is in flight.
        if (_controller.loading)
          LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.primary,
            backgroundColor: Colors.transparent,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'torrent.results_n'.tr(args: ['${_controller.results.length}']),
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _controller.results.length,
            separatorBuilder: (_, _) =>
                Divider(color: AppColors.divider, height: 1, indent: 31),
            itemBuilder: (context, index) {
              final result = _controller.results[index];
              return TorrentResultTile(
                result: result,
                onTap: () => _play(result),
                onLongPress: () => _showActions(result),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _centered({required Widget child}) => Center(child: child);

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
  }) =>
      _centered(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: AppColors.textHint),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
}
