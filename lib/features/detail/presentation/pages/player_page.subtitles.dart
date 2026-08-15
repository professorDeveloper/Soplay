// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerSubtitles on _PlayerPageState {
  /// Loads a track and reports whether it actually produced cues.
  ///
  /// Returns false — and leaves [_activeSubtitleIndex] on whatever was selected
  /// before — for a non-2xx response, an empty body, a parse failure, or a file
  /// that parses to zero cues. The old version returned void, swallowed every
  /// error, and marked the track active *before* the download started, so the
  /// sheet showed a ticked track and unlocked the sync control for a subtitle
  /// that had never loaded.
  Future<bool> _loadSubtitle(int index, {String declaredFormat = ''}) async {
    if (index < 0 || index >= _subtitles.length) {
      setState(() {
        _activeSubtitleIndex = -1;
        _captionFile = null;
      });
      return false;
    }
    final sub = _subtitles[index];
    SubtitleParseResult result;
    try {
      // ResponseType.bytes: Dio's string transformer always runs
      // utf8.decode(..., allowMalformed: true) and ignores the declared
      // charset, which destroys every cp1251/latin1 subtitle.
      final response = await Dio().get<List<int>>(
        sub.file,
        options: Options(
          responseType: ResponseType.bytes,
          headers: sub.headers.isEmpty ? null : sub.headers,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (!mounted) return false;
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        _plog('subtitle http $status for ${sub.file}', level: LogLevel.warn);
        _toast('player.subtitle_failed_download'.tr());
        return false;
      }
      result = parseSubtitleBytes(
        response.data ?? const <int>[],
        url: sub.file,
        declaredFormat: declaredFormat,
      );
    } catch (e) {
      _plog('subtitle load error: $e', level: LogLevel.warn);
      if (!mounted) return false;
      _toast('player.subtitle_failed_download'.tr());
      return false;
    }

    if (!mounted) return false;
    if (!result.isSuccess) {
      _plog('subtitle parse failed: ${result.failure}', level: LogLevel.warn);
      _toast(_subtitleFailureMessage(result.failure));
      return false;
    }

    _plog('subtitle loaded: ${result.captions.length} cues from ${sub.label}');
    setState(() {
      _activeSubtitleIndex = index;
      _captionFile = result.captions;
    });
    return true;
  }

  String _subtitleFailureMessage(SubtitleParseFailure? failure) {
    switch (failure) {
      case SubtitleParseFailure.archive:
        return 'player.subtitle_failed_archive'.tr();
      case SubtitleParseFailure.html:
        return 'player.subtitle_failed_html'.tr();
      case SubtitleParseFailure.unsupportedFormat:
        return 'player.subtitle_failed_format'.tr();
      case SubtitleParseFailure.empty:
      case SubtitleParseFailure.noCues:
      case null:
        return 'player.subtitle_failed_empty'.tr();
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
                focusColor: _kTvFocusFill,
                leading: const Icon(Icons.travel_explore_rounded,
                    color: Colors.white70, size: 20),
                title: Text('player.search_online'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _searchOnlineSubtitles();
                },
              ),
              if (_activeSubtitleIndex != -1)
              ListTile(
                focusColor: _kTvFocusFill,
                leading: const Icon(Icons.av_timer_rounded,
                    color: Colors.white70, size: 20),
                title: Text('player.subtitle_sync'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text('player.subtitle_sync_desc'.tr(),
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: (_subtitleOffsetMs.value == 0 &&
                        _subtitleRate.value == 1.0)
                    ? null
                    : Text(
                        [
                          if (_subtitleOffsetMs.value != 0)
                            _fmtSubtitleOffset(_subtitleOffsetMs.value),
                          if (_subtitleRate.value != 1.0)
                            _fmtSubtitleRate(_subtitleRate.value),
                        ].join(' · '),
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
    // Read the episode number from the entity — parsing the '<title> · <label>'
    // string picked up a digit in the TITLE (e.g. '3 Body Problem') instead of
    // the episode, querying the wrong episode's subtitles.
    if (_episodeIndex < 0 || _episodeIndex >= widget.args.episodes.length) {
      return null;
    }
    return widget.args.episodes[_episodeIndex].episode;
  }

  /// Season markers the providers put in episode labels / titles. The app has no
  /// season field of its own, and searching without a season returns e.g. S03E05
  /// subtitles while S01E05 is playing — a large constant desync.
  static final RegExp _seasonPattern = RegExp(
    r'(?:\bs\s*(\d{1,2})\s*[.\-_ ]?\s*e\s*\d{1,3}\b)'
    r'|(?:\b(?:season|сезон|сезона|fasl|mavsum)\s*[:.\-]?\s*(\d{1,2})\b)'
    r'|(?:\b(\d{1,2})\s*[-\s]?\s*(?:fasl|mavsum|сезон)\b)',
    caseSensitive: false,
  );

  int? _currentSeasonNumber() {
    if (!widget.args.isSerial) return null;
    final label = (_episodeIndex >= 0 &&
            _episodeIndex < widget.args.episodes.length)
        ? widget.args.episodes[_episodeIndex].label
        : '';
    for (final source in [label, widget.args.title]) {
      if (source.isEmpty) continue;
      final m = _seasonPattern.firstMatch(source);
      if (m == null) continue;
      final raw = m.group(1) ?? m.group(2) ?? m.group(3);
      final n = int.tryParse(raw ?? '');
      if (n != null && n > 0) return n;
    }
    return null;
  }

  String _wyzieKey() {
    final env = dotenv.isInitialized
        ? (dotenv.maybeGet('WYZIE_API_KEY') ?? '')
        : '';
    if (env.trim().isNotEmpty) return env.trim();
    return _hive.getOpenSubtitlesKey();
  }

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
                  season: _currentSeasonNumber(),
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

            if (!started) {
              started = true;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => runSearch());
            }

            // The sheet is mainAxisSize.min inside a full-height modal, so a
            // fixed 360px result list overflowed by 56px in landscape on a
            // 2340x1080 phone (411 logical px tall). Budget: header row 44 +
            // search field 60 + the 8/8 gaps = 120 of chrome, so the list gets
            // whatever is left of the viewport after the keyboard and the
            // system insets — 411 - 0 - 24 - 120 = 267 in landscape, and still
            // the full 360 in portrait (891 - 120 = 771, clamped).
            final mq = MediaQuery.of(ctx);
            const chromeHeight = 120.0;
            final listMaxHeight = (mq.size.height -
                    mq.viewInsets.bottom -
                    mq.padding.top -
                    mq.padding.bottom -
                    chromeHeight)
                .clamp(120.0, 360.0);

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
                      constraints: BoxConstraints(maxHeight: listMaxHeight),
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
        for (final (i, r) in results.take(60).indexed)
          ListTile(
            focusColor: _kTvFocusFill,
            // Put the remote on the first result as soon as the list renders,
            // so "search online" ends with something selected rather than a
            // list the D-pad has to find its way into.
            autofocus: isTvPlatform && i == 0,
            dense: true,
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
    final name = sub.fileName.isNotEmpty ? sub.fileName : sub.display;
    final entity = SubtitleEntity(
      label: name,
      file: sub.url,
    );
    setState(() => _subtitles = [..._subtitles, entity]);
    final added = _subtitles.length - 1;
    // The "loaded" toast is gated on the real outcome — _loadSubtitle already
    // reported the reason if it failed. A track that never loaded is dropped
    // again so it cannot sit in the sheet pretending to work.
    final ok = await _loadSubtitle(added, declaredFormat: sub.format);
    if (!mounted) return;
    if (ok) {
      _toast('player.subtitle_loaded'.tr());
    } else if (added < _subtitles.length && _activeSubtitleIndex != added) {
      setState(() => _subtitles = [..._subtitles]..removeAt(added));
    }
  }

  String _fmtSubtitleOffset(int ms) {
    final s = (ms / 1000.0).abs().toStringAsFixed(2);
    final sign = ms > 0 ? '+' : (ms < 0 ? '−' : '');
    return '$sign$s s';
  }

  String _fmtSubtitleRate(double rate) =>
      rate == 1.0 ? '1×' : '${rate.toStringAsFixed(5)}×';

  /// Sync is stored per title+episode: a shift tuned for episode 1 must not
  /// carry into episode 2, and it must survive closing the player.
  String get _subtitleSyncKey {
    final ep = _currentEpisodeNumber();
    return '${widget.args.provider}::${widget.args.title}'
        '${ep == null ? '' : '::ep$ep'}';
  }

  void _restoreSubtitleSync() {
    final key = _subtitleSyncKey;
    _subtitleOffsetMs.value = _hive.getSubtitleOffsetMs(key);
    _subtitleRate.value = _hive.getSubtitleRate(key);
  }

  void _persistSubtitleSync() {
    final key = _subtitleSyncKey;
    unawaited(_hive.saveSubtitleOffsetMs(key, _subtitleOffsetMs.value));
    unawaited(_hive.saveSubtitleRate(key, _subtitleRate.value));
  }

  /// Common telecine/PAL conversions. A 25fps subtitle over 23.976fps content
  /// drifts ~2.5s per minute, which no constant offset can correct.
  static const List<(String, double)> _subtitleRatePresets = [
    ('1.0', 1.0),
    ('25 → 23.976', 25.0 / 23.976),
    ('23.976 → 25', 23.976 / 25.0),
    ('30 → 29.97', 30.0 / 29.97),
    ('24 → 23.976', 24.0 / 23.976),
  ];

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
              _subtitleOffsetMs.value = clamped;
              _persistSubtitleSync();
              setSheet(() {});
            }

            void setRate(double rate) {
              _subtitleRate.value = rate.clamp(0.5, 2.0);
              _persistSubtitleSync();
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
                            onPressed: () {
                              _subtitleRate.value = 1.0;
                              setOffset(0);
                            },
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
                    // The ±0.1/±0.5 buttons above already cover this on a
                    // remote, and a focused Material slider would trap the
                    // D-pad (it binds up/down as well as left/right), so TV
                    // drops the slider rather than adapting it.
                    if (!isTvPlatform)
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
                    const SizedBox(height: 6),
                    const Divider(color: Colors.white12, height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          const Icon(Icons.speed_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('player.subtitle_rate'.tr(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Text(_fmtSubtitleRate(_subtitleRate.value),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text('player.subtitle_rate_help'.tr(),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, rate) in _subtitleRatePresets)
                            ChoiceChip(
                              label: Text(
                                rate == 1.0
                                    ? 'player.subtitle_rate_off'.tr()
                                    : '$label fps',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected:
                                  (_subtitleRate.value - rate).abs() < 0.00001,
                              onSelected: (_) => setRate(rate),
                              backgroundColor: Colors.white10,
                              selectedColor: AppColors.primary,
                              labelStyle: const TextStyle(color: Colors.white),
                              side: const BorderSide(color: Colors.white24),
                              showCheckmark: false,
                            ),
                        ],
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
                            child: isTvPlatform
                                ? _TvStepper(
                                    display:
                                        '${_subtitleStyle.fontSize.round()}',
                                    onDecrease: _subtitleStyle.fontSize > 12
                                        ? () => apply(
                                              _subtitleStyle.copyWith(
                                                fontSize: (_subtitleStyle
                                                            .fontSize -
                                                        2)
                                                    .clamp(12, 32),
                                              ),
                                            )
                                        : null,
                                    onIncrease: _subtitleStyle.fontSize < 32
                                        ? () => apply(
                                              _subtitleStyle.copyWith(
                                                fontSize: (_subtitleStyle
                                                            .fontSize +
                                                        2)
                                                    .clamp(12, 32),
                                              ),
                                            )
                                        : null,
                                  )
                                : SliderTheme(
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
                      child: isTvPlatform
                          ? _TvStepper(
                              display:
                                  '${(_subtitleStyle.bgOpacity * 100).round()}%',
                              onDecrease: _subtitleStyle.bgOpacity > 0
                                  ? () => apply(
                                        _subtitleStyle.copyWith(
                                          bgOpacity:
                                              (_subtitleStyle.bgOpacity - 0.1)
                                                  .clamp(0.0, 1.0),
                                        ),
                                      )
                                  : null,
                              onIncrease: _subtitleStyle.bgOpacity < 1
                                  ? () => apply(
                                        _subtitleStyle.copyWith(
                                          bgOpacity:
                                              (_subtitleStyle.bgOpacity + 0.1)
                                                  .clamp(0.0, 1.0),
                                        ),
                                      )
                                  : null,
                            )
                          : SliderTheme(
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
                        focusColor: _kTvFocusFill,
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
        child: ListenableBuilder(
          listenable: Listenable.merge([_subtitleOffsetMs, _subtitleRate, c]),
          builder: (_, _) {
            final rate = _subtitleRate.value;
            var position =
                c.value.position -
                    Duration(milliseconds: _subtitleOffsetMs.value);
            // Map the video clock onto the subtitle's own timeline: a 25fps
            // subtitle over 23.976fps content needs its timestamps stretched,
            // which is a division here, not a shift.
            if (rate != 1.0 && rate > 0) {
              position = Duration(
                microseconds: (position.inMicroseconds / rate).round(),
              );
            }
            final active = _captionAt(captions, position);
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
    );
  }

  /// The cue on screen at [position]. Cues are sorted by start, so this binary
  /// searches for the LAST one that starts at or before [position] — the old
  /// linear scan took the FIRST containing cue, which let a stale overlapping
  /// cue hold the screen and read as "too slow".
  Caption? _captionAt(List<Caption> cues, Duration position) {
    var lo = 0;
    var hi = cues.length - 1;
    var idx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].start <= position) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    for (var i = idx; i >= 0; i--) {
      if (position <= cues[i].end) return cues[i];
      // Sorted by start, so once we are well behind nothing earlier can still
      // be on screen — this only walks back over genuine overlaps.
      if (position - cues[i].start > const Duration(seconds: 30)) break;
    }
    return null;
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
