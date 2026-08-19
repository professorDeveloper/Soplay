import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';

/// Live TV.
///
/// A line-up rather than a catalogue: channels are picked in a second, so the
/// screen is built for scanning — logo-forward cards, categories across the
/// top, and the ones you actually watch pinned above everything else.
class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key});

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> {
  final LiveTvService _service = getIt<LiveTvService>();
  final _search = TextEditingController();

  List<LiveCategory> _all = const [];
  Set<String> _favourites = <String>{};
  String _category = '';
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _favourites = _readFavourites();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Set<String> _readFavourites() =>
      getIt<HiveService>().getLiveTvFavourites().toSet();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lineup = await _service.lineup();
      if (!mounted) return;
      setState(() {
        _all = lineup;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'live_tv.load_failed'.tr();
      });
      // A failed pull-to-refresh keeps the line-up on screen, so the failure
      // has to be said somewhere other than the error state.
      if (_all.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_error!),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _toggleFavourite(LiveChannel channel) {
    setState(() {
      if (!_favourites.remove(channel.id)) _favourites.add(channel.id);
    });
    getIt<HiveService>().setLiveTvFavourites(_favourites.toList());
  }

  void _play(LiveChannel channel) {
    context.push(
      '/player',
      extra: PlayerArgs(
        title: channel.name,
        provider: 'live',
        headers: const {},
        movieUrl: channel.streamUrl,
        thumbnail: channel.logoUrl,
        // Live has no episodes and nothing to resume to, and offering a
        // download for a stream with no end would be a lie.
        type: 'live',
        showDownloadAction: false,
      ),
    );
  }

  List<LiveChannel> get _flat => [
    for (final category in _all) ...category.channels,
  ];

  List<LiveChannel> get _visible {
    final query = _query.trim().toLowerCase();
    return _flat.where((c) {
      if (_category.isNotEmpty && c.category != _category) return false;
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query);
    }).toList(growable: false);
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
          'live_tv.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    // Gated on there being nothing to show: a refresh over a loaded line-up
    // used to swap the whole screen for a spinner and back again.
    if (_loading && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null && _all.isEmpty) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        text: _error!,
        actionLabel: 'live_tv.retry'.tr(),
        onAction: _load,
      );
    }
    if (_all.isEmpty) {
      return _Empty(icon: Icons.live_tv_rounded, text: 'live_tv.empty'.tr());
    }

    final visible = _visible;
    final favourites = _flat
        .where((c) => _favourites.contains(c.id))
        .toList(growable: false);
    final showFavourites =
        favourites.isNotEmpty && _query.isEmpty && _category.isEmpty;

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'live_tv.search_hint'.tr(),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: _CategoryBar(
              categories: [for (final c in _all) c.name],
              selected: _category,
              onSelect: (value) => setState(() => _category = value),
            ),
          ),

          if (showFavourites) ...[
            _Header(label: 'live_tv.favourites'.tr()),
            _Grid(
              channels: favourites,
              favourites: _favourites,
              onPlay: _play,
              onFavourite: _toggleFavourite,
            ),
          ],

          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: _Empty(
                  icon: Icons.search_off_rounded,
                  text: 'live_tv.no_match'.tr(),
                ),
              ),
            )
          else ...[
            if (showFavourites) _Header(label: 'live_tv.all_channels'.tr()),
            _Grid(
              channels: visible,
              favourites: _favourites,
              onPlay: _play,
              onFavourite: _toggleFavourite,
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final value = i == 0 ? '' : categories[i - 1];
          final label = i == 0 ? 'live_tv.all'.tr() : value;
          final active = value == selected;
          return Material(
            color: active
                ? AppColors.primary.withValues(alpha: 0.16)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelect(value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: active ? AppColors.primary : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: active ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.channels,
    required this.favourites,
    required this.onPlay,
    required this.onFavourite,
  });

  final List<LiveChannel> channels;
  final Set<String> favourites;
  final ValueChanged<LiveChannel> onPlay;
  final ValueChanged<LiveChannel> onFavourite;

  @override
  Widget build(BuildContext context) {
    // Channel logos are wide, not poster-shaped, so the cell is landscape and
    // the count follows the width rather than a fixed number.
    const gutter = 14.0;
    const spacing = 10.0;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 5 : (width >= 620 ? 4 : 3);
    final cell = (width - gutter * 2 - spacing * (columns - 1)) / columns;
    final caption = _ChannelCard.reserveCaption(context);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: gutter),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          // The logo box is what the cell is for, so the caption's two lines
          // are added to it rather than taken out of it — a fixed ratio let a
          // long name eat the logo, and a one-line name grow it.
          childAspectRatio: cell / (cell * 0.73 + caption + 9),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ChannelCard(
            channel: channels[i],
            favourite: favourites.contains(channels[i].id),
            captionHeight: caption,
            onPlay: () => onPlay(channels[i]),
            onFavourite: () => onFavourite(channels[i]),
          ),
          childCount: channels.length,
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.channel,
    required this.favourite,
    required this.captionHeight,
    required this.onPlay,
    required this.onFavourite,
  });

  static const double _fontSize = 11.5;
  static const double _lineHeight = 1.2;

  /// Two lines, always. Channel names run from "TV1" to "Discovery Science HD",
  /// and letting the caption size itself left every logo in a row at a
  /// different scale.
  static double reserveCaption(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight * 2;

  final LiveChannel channel;
  final bool favourite;
  final double captionHeight;
  final VoidCallback onPlay;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        onLongPress: onFavourite,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: favourite
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: channel.logoUrl == null
                            ? _Fallback(name: channel.name)
                            : CachedNetworkImage(
                                imageUrl: channel.logoUrl!,
                                fit: BoxFit.contain,
                                // Logos come from wherever the playlist points,
                                // and a dead one is common — the initial reads
                                // better than a broken-image glyph.
                                errorWidget: (_, _, _) =>
                                    _Fallback(name: channel.name),
                                placeholder: (_, _) =>
                                    _Fallback(name: channel.name),
                              ),
                      ),
                    ),
                    if (favourite)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(
                          Icons.star_rounded,
                          size: 15,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
                child: SizedBox(
                  height: captionHeight,
                  child: Center(
                    child: Text(
                      channel.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: _fontSize,
                        height: _lineHeight,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
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
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.textHint.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
