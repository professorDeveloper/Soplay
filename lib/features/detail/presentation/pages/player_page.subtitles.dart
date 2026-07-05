// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerSubtitles on _PlayerPageState {
  Future<void> _loadSubtitle(int index) async {
    if (index < 0 || index >= _subtitles.length) {
      setState(() {
        _activeSubtitleIndex = -1;
        _captionFile = null;
      });
      return;
    }
    setState(() => _activeSubtitleIndex = index);
    final sub = _subtitles[index];
    try {
      final response = await Dio().get<String>(
        sub.file,
        options: Options(
          responseType: ResponseType.plain,
          headers: sub.headers.isEmpty ? null : sub.headers,
        ),
      );
      if (!mounted) return;
      final body = response.data;
      if (body != null && body.isNotEmpty) {
        final isVtt =
            sub.file.toLowerCase().endsWith('.vtt') ||
            body.trimLeft().startsWith('WEBVTT');
        setState(() {
          _captionFile = isVtt
              ? WebVTTCaptionFile(body)
              : SubRipCaptionFile(body);
        });
      }
    } catch (e) {
      _plog('subtitle load error: $e', level: LogLevel.warn);
    }
  }

  void _disableSubtitle() {
    setState(() {
      _activeSubtitleIndex = -1;
      _captionFile = null;
    });
  }

  void _openSubtitleSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.subtitles_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.subtitles'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              _OptionTile(
                label: 'player.off'.tr(),
                selected: _activeSubtitleIndex == -1,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _disableSubtitle();
                },
              ),
              for (var i = 0; i < _subtitles.length; i++)
                _OptionTile(
                  label: _subtitles[i].label,
                  selected: i == _activeSubtitleIndex,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _loadSubtitle(i);
                  },
                ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.travel_explore_rounded,
                    color: Colors.white70, size: 20),
                title: Text('player.search_online'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _searchOnlineSubtitles();
                },
              ),
              // Subtitle sync only has a visible effect when a subtitle is on.
              if (_activeSubtitleIndex != -1)
              ListTile(
                leading: const Icon(Icons.av_timer_rounded,
                    color: Colors.white70, size: 20),
                title: Text('player.subtitle_sync'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text('player.subtitle_sync_desc'.tr(),
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: _subtitleOffsetMs.value == 0
                    ? null
                    : Text(_fmtSubtitleOffset(_subtitleOffsetMs.value),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSubtitleSyncSheet();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _promptWyzieKey() async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('player.subtitle_api_key'.tr(),
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'player.wyzie_key_hint'.tr(),
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'player.api_key'.tr(),
                hintStyle: const TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('general.save'.tr()),
          ),
        ],
      ),
    );
    if (key == null || key.isEmpty) return null;
    await _hive.saveOpenSubtitlesKey(key);
    return key;
  }

  int? _currentEpisodeNumber() {
    if (!widget.args.isSerial) return null;
    final m = RegExp(r'(\d+)').firstMatch(_episodeTitle());
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  String _wyzieKey() {
    final env = dotenv.isInitialized
        ? (dotenv.maybeGet('WYZIE_API_KEY') ?? '')
        : '';
    if (env.trim().isNotEmpty) return env.trim();
    return _hive.getOpenSubtitlesKey();
  }

  /// One combined sheet: a query field plus inline results, so searching a
  /// subtitle is a single screen (the old flow chained a query dialog → a
  /// separate results sheet, which felt clunky — especially on mobile). It
  /// auto-runs once with the title prefilled. Works on mobile and desktop.
  Future<void> _searchOnlineSubtitles() async {
    var key = _wyzieKey();
    if (key.isEmpty) {
      key = await _promptWyzieKey() ?? '';
      if (key.isEmpty || !mounted) return;
    }
    final wyzieKey = key;
    final queryCtrl = TextEditingController(
      text: widget.args.title.replaceAll(RegExp(r'\(.*?\)'), '').trim(),
    );

    await showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      desktopMaxWidth: 520,
      builder: (sheetCtx) {
        var started = false;
        var loading = false;
        var searched = false;
        String? error;
        List<OnlineSubtitle> results = const [];

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> runSearch() async {
              final q = queryCtrl.text.trim();
              if (q.isEmpty || loading) return;
              FocusScope.of(ctx).unfocus();
              setSheet(() {
                loading = true;
                searched = true;
                error = null;
              });
              try {
                final r = await OnlineSubtitlesService.search(
                  wyzieKey: wyzieKey,
                  title: q,
                  isSerial: widget.args.isSerial,
                  episode: _currentEpisodeNumber(),
                );
                if (!ctx.mounted) return;
                setSheet(() {
                  results = r;
                  loading = false;
                });
              } catch (e) {
                if (!ctx.mounted) return;
                setSheet(() {
                  error = '$e';
                  results = const [];
                  loading = false;
                });
              }
            }

            // Auto-run the first search with the prefilled title.
            if (!started) {
              started = true;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => runSearch());
            }

            return SafeArea(
              child: Padding(
                padding:
                    EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.travel_explore_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('player.search_subtitles'.tr(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(),
                        decoration: InputDecoration(
                          hintText: 'player.subtitle_search_hint'.tr(),
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'general.search'.tr(),
                            icon: loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white70))
                                : const Icon(Icons.search_rounded,
                                    color: Colors.white70),
                            onPressed: loading ? null : runSearch,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: _subtitleResults(
                          sheetCtx, loading, searched, error, results),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _subtitleResults(
    BuildContext sheetCtx,
    bool loading,
    bool searched,
    String? error,
    List<OnlineSubtitle> results,
  ) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('player.search_failed'.tr(args: [error]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ),
      );
    }
    if (searched && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('player.no_subtitles_found'.tr(),
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        for (final r in results.take(60))
          ListTile(
            dense: true,
            // Show the exact release / file name so the user can match the
            // subtitle to their video.
            title: Text(r.fileName.isNotEmpty ? r.fileName : r.display,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(
                [
                  r.language,
                  if (r.fileName.isNotEmpty &&
                      r.display.isNotEmpty &&
                      r.display.toUpperCase() != r.language)
                    r.display,
                  if (r.format.isNotEmpty) r.format,
                  if (r.hearingImpaired) 'CC',
                  '${r.downloadCount} ↓',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _applyOnlineSubtitle(r);
            },
          ),
      ],
    );
  }

  Future<void> _applyOnlineSubtitle(OnlineSubtitle sub) async {
    if (sub.url.isEmpty) return;
    _toast('player.loading_subtitle'.tr());
    // Prefer the exact release name so the loaded-subtitles list shows it.
    final name = sub.fileName.isNotEmpty ? sub.fileName : sub.display;
    final entity = SubtitleEntity(
      label: name,
      file: sub.url,
    );
    setState(() => _subtitles = [..._subtitles, entity]);
    await _loadSubtitle(_subtitles.length - 1);
    if (mounted) _toast('player.subtitle_loaded'.tr());
  }

  String _fmtSubtitleOffset(int ms) {
    final s = (ms / 1000.0).abs().toStringAsFixed(2);
    final sign = ms > 0 ? '+' : (ms < 0 ? '−' : '');
    return '$sign$s s';
  }

  /// Subtitle sync: shift subtitle timing earlier (−) or later (+) so it lines
  /// up with the audio. Adjustable via fine buttons and a slider (thumb). Works
  /// on mobile and desktop.
  void _openSubtitleSyncSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      desktopMaxWidth: 460,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void setOffset(int ms) {
              final clamped = ms.clamp(-20000, 20000);
              // Only the overlay listens to this notifier, so a drag no longer
              // rebuilds the whole player. setSheet refreshes this sheet's own
              // number/slider.
              _subtitleOffsetMs.value = clamped;
              setSheet(() {});
            }

            Widget btn(String label, int delta) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => setOffset(_subtitleOffsetMs.value + delta),
                    child: Text(label),
                  ),
                );

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.av_timer_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('player.subtitle_sync'.tr(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ),
                          TextButton.icon(
                            onPressed: () => setOffset(0),
                            icon: const Icon(Icons.restart_alt_rounded,
                                size: 16, color: Colors.white70),
                            label: Text('player.reset'.tr(),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Text(
                          'player.subtitle_sync_help'.tr(),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          _fmtSubtitleOffset(_subtitleOffsetMs.value),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        btn('−0.5', -500),
                        btn('−0.1', -100),
                        btn('+0.1', 100),
                        btn('+0.5', 500),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: AppColors.primary,
                          overlayColor:
                              AppColors.primary.withValues(alpha: 0.15),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          min: -10000,
                          max: 10000,
                          divisions: 400,
                          value: _subtitleOffsetMs.value
                              .toDouble()
                              .clamp(-10000, 10000),
                          label: _fmtSubtitleOffset(_subtitleOffsetMs.value),
                          onChanged: (v) => setOffset(v.round()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openSubtitleAppearanceSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      desktopMaxWidth: 520,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void apply(SubtitleStyle next) {
              setSheet(() {});
              _applySubtitleStyle(next);
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.subtitles_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'player.subtitle_style'.tr(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => apply(SubtitleStyle.defaults()),
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 16,
                              color: Colors.white70,
                            ),
                            label: Text(
                              'player.reset'.tr(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    _SubtitlePreview(style: _subtitleStyle),
                    const SizedBox(height: 4),
                    _SheetSectionLabel('player.font_size'.tr()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Text(
                            'A',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(ctx).copyWith(
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: Colors.white12,
                                thumbColor: AppColors.primary,
                                overlayColor: AppColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                min: 12,
                                max: 32,
                                divisions: 20,
                                value: _subtitleStyle.fontSize.clamp(12, 32),
                                label: '${_subtitleStyle.fontSize.round()}',
                                onChanged: (v) => apply(
                                  _subtitleStyle.copyWith(fontSize: v),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            'A',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${_subtitleStyle.fontSize.round()}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SheetSectionLabel('player.text_color'.tr()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        children: [
                          for (final c in _subtitleColorPresets)
                            _ColorDot(
                              color: Color(c),
                              selected: _subtitleStyle.textColor == c,
                              onTap: () => apply(
                                _subtitleStyle.copyWith(textColor: c),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _SheetSectionLabel('player.background'.tr()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: AppColors.primary,
                          overlayColor: AppColors.primary.withValues(
                            alpha: 0.15,
                          ),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          min: 0,
                          max: 1,
                          divisions: 20,
                          value: _subtitleStyle.bgOpacity.clamp(0, 1),
                          label:
                              '${(_subtitleStyle.bgOpacity * 100).round()}%',
                          onChanged: (v) =>
                              apply(_subtitleStyle.copyWith(bgOpacity: v)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'player.none'.tr(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'player.solid'.tr(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SheetSectionLabel('player.edge'.tr()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ChipRow<SubtitleEdge>(
                        value: _subtitleStyle.edge,
                        items: [
                          (SubtitleEdge.none, 'player.none'.tr()),
                          (SubtitleEdge.shadow, 'player.shadow'.tr()),
                          (SubtitleEdge.outline, 'player.outline'.tr()),
                        ],
                        onChanged: (v) =>
                            apply(_subtitleStyle.copyWith(edge: v)),
                      ),
                    ),
                    _SheetSectionLabel('player.position'.tr()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ChipRow<SubtitlePosition>(
                        value: _subtitleStyle.position,
                        items: [
                          (SubtitlePosition.lower, 'player.lower'.tr()),
                          (SubtitlePosition.normal, 'player.default'.tr()),
                          (SubtitlePosition.higher, 'player.higher'.tr()),
                        ],
                        onChanged: (v) =>
                            apply(_subtitleStyle.copyWith(position: v)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: InkWell(
                        onTap: () =>
                            apply(_subtitleStyle.copyWith(bold: !_subtitleStyle.bold)),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.format_bold_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'player.bold'.tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Switch.adaptive(
                                value: _subtitleStyle.bold,
                                activeThumbColor: AppColors.primary,
                                onChanged: (v) =>
                                    apply(_subtitleStyle.copyWith(bold: v)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSubtitleOverlay() {
    final c = _controller;
    final captions = _captionFile;
    if (c == null || !c.value.isInitialized || captions == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 16,
      right: 16,
      bottom: _subtitleBottomOffset,
      child: IgnorePointer(
        // Outer: rebuild when the user changes the sync offset (even while
        // paused). Inner: rebuild as the video position advances.
        child: ValueListenableBuilder<int>(
          valueListenable: _subtitleOffsetMs,
          builder: (_, offsetMs, _) => ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, value, _) {
              // Apply the user's sync offset: positive shifts subtitles later.
              final position =
                  value.position - Duration(milliseconds: offsetMs);
              Caption? active;
              for (final caption in captions.captions) {
                if (position >= caption.start && position <= caption.end) {
                  active = caption;
                  break;
                }
              }
              if (active == null || active.text.isEmpty) {
                return const SizedBox.shrink();
              }
              return Align(
                alignment: Alignment.bottomCenter,
                child: _styledSubtitle(active.text),
              );
            },
          ),
        ),
      ),
    );
  }

  double get _subtitleBottomOffset {
    final base = _controlsVisible ? 100.0 : 24.0;
    switch (_subtitleStyle.position) {
      case SubtitlePosition.lower:
        return base - 12;
      case SubtitlePosition.normal:
        return base;
      case SubtitlePosition.higher:
        return base + 60;
    }
  }

  Widget _styledSubtitle(String text) {
    final style = _subtitleStyle;
    final color = Color(style.textColor);
    final weight = style.bold ? FontWeight.w800 : FontWeight.w500;
    final hasBg = style.bgOpacity > 0.01;

    List<Shadow>? shadows;
    Paint? strokePaint;
    switch (style.edge) {
      case SubtitleEdge.none:
        break;
      case SubtitleEdge.shadow:
        shadows = const [
          Shadow(
            color: Color(0xCC000000),
            offset: Offset(0, 1.5),
            blurRadius: 4,
          ),
        ];
      case SubtitleEdge.outline:
        strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF000000);
    }

    Widget textWidget = Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: style.fontSize,
        fontWeight: weight,
        height: 1.3,
        shadows: shadows,
      ),
    );

    if (strokePaint != null) {
      textWidget = Stack(
        alignment: Alignment.center,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: style.fontSize,
              fontWeight: weight,
              height: 1.3,
              foreground: strokePaint,
            ),
          ),
          textWidget,
        ],
      );
    }

    if (!hasBg) return textWidget;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: style.bgOpacity),
        borderRadius: BorderRadius.circular(6),
      ),
      child: textWidget,
    );
  }

  void _applySubtitleStyle(SubtitleStyle next) {
    setState(() => _subtitleStyle = next);
    _hive.saveSubtitleStyle(next);
  }
}
