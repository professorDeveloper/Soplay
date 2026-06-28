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
    showModalBottomSheet<void>(
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.subtitles_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Subtitles',
                      style: TextStyle(
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
                label: 'Off',
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
                title: const Text('Search online',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _searchOnlineSubtitles();
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
        title: const Text('Subtitle API key',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Claim a free Wyzie key at store.wyzie.io/redeem, then paste it here.',
              style: TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'API key',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
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

  Future<String?> _promptSearchQuery(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Search subtitles',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Title / movie name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Future<void> _searchOnlineSubtitles() async {
    var key = _wyzieKey();
    if (key.isEmpty) {
      key = await _promptWyzieKey() ?? '';
      if (key.isEmpty || !mounted) return;
    }
    final initial = widget.args.title.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    final query = await _promptSearchQuery(initial);
    if (query == null || query.trim().isEmpty || !mounted) return;
    _toast('Searching subtitles…');
    try {
      final results = await OnlineSubtitlesService.search(
        wyzieKey: key,
        title: query.trim(),
        isSerial: widget.args.isSerial,
        episode: _currentEpisodeNumber(),
      );
      if (!mounted) return;
      if (results.isEmpty) {
        _toast('No subtitles found');
        return;
      }
      _pickOnlineSubtitle(results);
    } catch (e) {
      if (mounted) _toast('Search failed: $e');
    }
  }

  void _pickOnlineSubtitle(List<OnlineSubtitle> results) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('Online subtitles · ${results.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),
            const Divider(color: Colors.white12, height: 1),
            for (final r in results.take(60))
              ListTile(
                dense: true,
                title: Text(
                    '${r.display}${r.hearingImpaired ? ' [CC]' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: Text('${r.language} · ${r.downloadCount} downloads',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _applyOnlineSubtitle(r);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _applyOnlineSubtitle(OnlineSubtitle sub) async {
    if (sub.url.isEmpty) return;
    _toast('Loading subtitle…');
    final entity = SubtitleEntity(
      label: '${sub.display} (online)',
      file: sub.url,
    );
    setState(() => _subtitles = [..._subtitles, entity]);
    await _loadSubtitle(_subtitles.length - 1);
    if (mounted) _toast('Subtitle loaded');
  }

  void _openSubtitleAppearanceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
                          const Expanded(
                            child: Text(
                              'Subtitle style',
                              style: TextStyle(
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
                            label: const Text(
                              'Reset',
                              style: TextStyle(
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
                    _SheetSectionLabel('Font size'),
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
                    _SheetSectionLabel('Text color'),
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
                    _SheetSectionLabel('Background'),
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
                        children: const [
                          Text(
                            'None',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Solid',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SheetSectionLabel('Edge'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ChipRow<SubtitleEdge>(
                        value: _subtitleStyle.edge,
                        items: const [
                          (SubtitleEdge.none, 'None'),
                          (SubtitleEdge.shadow, 'Shadow'),
                          (SubtitleEdge.outline, 'Outline'),
                        ],
                        onChanged: (v) =>
                            apply(_subtitleStyle.copyWith(edge: v)),
                      ),
                    ),
                    _SheetSectionLabel('Position'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ChipRow<SubtitlePosition>(
                        value: _subtitleStyle.position,
                        items: const [
                          (SubtitlePosition.lower, 'Lower'),
                          (SubtitlePosition.normal, 'Default'),
                          (SubtitlePosition.higher, 'Higher'),
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
                              const Expanded(
                                child: Text(
                                  'Bold',
                                  style: TextStyle(
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
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (_, value, _) {
            final position = value.position;
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
