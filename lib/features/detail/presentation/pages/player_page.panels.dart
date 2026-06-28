part of 'player_page.dart';

extension _PlayerPanels on _PlayerPageState {
  String _langLabel(String lang) {
    switch (lang.toLowerCase()) {
      case _kSubLang:
        return 'Subtitled (SUB)';
      case _kDubLang:
        return 'Dubbed (DUB)';
      case 'softsub':
        return 'Soft subtitles';
      default:
        return lang.toUpperCase();
    }
  }

  void _openLangSheet() {
    final langs = _availableLangsForCurrentEpisode();
    if (langs.isEmpty) return;
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
                      Icons.translate_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Audio language',
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
              for (final l in langs)
                _OptionTile(
                  label: _langLabel(l),
                  selected: l == _currentLang,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _switchLang(l);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettingsSheet() {
    final hasQualities = _videoSources.length > 1;
    final langs = _availableLangsForCurrentEpisode();
    final hasLangs = langs.length > 1;
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
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Settings',
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
              _SettingsTile(
                icon: Icons.speed_rounded,
                label: 'Speed',
                value:
                    '${_playbackSpeed.toStringAsFixed(_playbackSpeed == _playbackSpeed.roundToDouble() ? 0 : 2)}x',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSpeedSheet();
                },
              ),
              _SettingsTile(
                icon: Icons.aspect_ratio_rounded,
                label: 'Aspect',
                value: _fitLabel(_fit),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openFitSheet();
                },
              ),
              if (hasQualities)
                _SettingsTile(
                  icon: Icons.high_quality_rounded,
                  label: 'Quality',
                  value: _currentQuality ?? '—',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openPanel(_SidePanel.quality);
                  },
                ),
              if (hasLangs)
                _SettingsTile(
                  icon: Icons.translate_rounded,
                  label: 'Audio language',
                  value: _currentLang == null ? '—' : _langLabel(_currentLang!),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openLangSheet();
                  },
                ),
              _SettingsTile(
                icon: Icons.subtitles_outlined,
                label: 'Subtitles',
                value: _subtitles.isEmpty
                    ? 'Search'
                    : _activeSubtitleIndex >= 0
                    ? _subtitles[_activeSubtitleIndex].label
                    : 'Off',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSubtitleSheet();
                },
              ),
              if (_subtitles.isNotEmpty)
                _SettingsTile(
                  icon: Icons.text_fields_rounded,
                  label: 'Subtitle style',
                  value: '${_subtitleStyle.fontSize.round()}px',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openSubtitleAppearanceSheet();
                  },
                ),
              if (!hasLangs)
                const _SettingsTile(
                  icon: Icons.audiotrack_outlined,
                  label: 'Audio track',
                  value: 'Coming soon',
                  onTap: null,
                ),
              if (widget.args.showDownloadAction &&
                  widget.args.provider != 'uzmovi')
                _SettingsTile(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  value: '',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startDownload();
                  },
                ),
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                label: 'Diagnostics / Logs',
                value: _isLive ? 'live' : '',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  LogViewerSheet.show(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
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
                    Icon(Icons.speed_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Playback speed',
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
              for (final s in speeds)
                _OptionTile(
                  label:
                      '${s.toStringAsFixed(s == s.roundToDouble() ? 0 : 2)}x',
                  selected: s == _playbackSpeed,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setSpeed(s);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openFitSheet() {
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
                      Icons.aspect_ratio_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Aspect ratio',
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
              for (final fit in _PlayerFit.values)
                _OptionTile(
                  label: _fitLabel(fit),
                  selected: fit == _fit,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setFit(fit);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel() {
    final isQuality = _panel == _SidePanel.quality;
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: 320,
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      isQuality ? 'Quality' : 'Episodes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _closePanel,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isQuality
                    ? ListView.separated(
                        itemCount: _videoSources.length,
                        separatorBuilder: (_, _) => Divider(
                          color: Colors.white.withValues(alpha: 0.06),
                          height: 1,
                        ),
                        itemBuilder: (_, i) {
                          final src = _videoSources[i];
                          return _QualityRow(
                            source: src,
                            isActive: src.quality == _currentQuality,
                            onTap: () => _switchQuality(src),
                          );
                        },
                      )
                    : ListView.separated(
                        itemCount: widget.args.episodes.length,
                        separatorBuilder: (_, _) => Divider(
                          color: Colors.white.withValues(alpha: 0.06),
                          height: 1,
                        ),
                        itemBuilder: (_, i) => _EpisodeRow(
                          episode: widget.args.episodes[i],
                          isActive: i == _episodeIndex,
                          onTap: () => _loadEpisode(i),
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
