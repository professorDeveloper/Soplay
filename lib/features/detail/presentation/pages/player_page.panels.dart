// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerPanels on _PlayerPageState {
  String _langLabel(String lang) {
    switch (lang.toLowerCase()) {
      case _kSubLang:
        return 'player.lang_sub'.tr();
      case _kDubLang:
        return 'player.lang_dub'.tr();
      case 'softsub':
        return 'player.lang_softsub'.tr();
      default:
        return lang.toUpperCase();
    }
  }

  void _openLangSheet() {
    final langs = _availableLangsForCurrentEpisode();
    if (langs.isEmpty) return;
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
                      Icons.translate_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.audio_language'.tr(),
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

  List<String> get _sourceLabels => [for (final s in _videoSources) s.quality];

  List<String> get _sourceServers => VideoOptionGroups.servers(_sourceLabels);

  /// The host currently playing, or null before the first source resolves.
  ///
  /// Nullable on purpose: serverOf('') answers with the "Default" placeholder,
  /// which the bar and the settings sheet were painting as if it were a real
  /// host name.
  String? get _currentServer {
    final quality = _currentQuality;
    if (quality == null) return null;
    return VideoOptionGroups.serverOf(quality);
  }

  /// Positions in [_videoSources] the current server offers.
  List<int> get _currentServerSources {
    final labels = _sourceLabels;
    final indices = VideoOptionGroups.indicesFor(labels, _currentServer ?? '');
    // Until the first source resolves there is no current server; offering
    // everything beats offering nothing.
    return indices.isEmpty
        ? [for (var i = 0; i < labels.length; i++) i]
        : indices;
  }

  String _qualityLabel(String label) {
    final quality = VideoOptionGroups.qualityOf(label);
    return quality.isEmpty ? label : quality;
  }

  /// [_QualityRow] paints the label verbatim, and every label in a one-server
  /// list starts with that server's name — so hand it a display-only copy.
  VideoSourceEntity _resolutionOnly(VideoSourceEntity source) =>
      VideoSourceEntity(
        quality: _qualityLabel(source.quality),
        videoUrl: source.videoUrl,
        isDefault: source.isDefault,
        accessible: source.accessible,
      );

  void _openServerSheet() {
    final labels = _sourceLabels;
    final servers = _sourceServers;
    if (servers.length < 2) return;
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
                      Icons.dns_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.server'.tr(),
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
              for (final server in servers)
                _ServerTile(
                  label: server,
                  qualities: VideoOptionGroups.qualitiesFor(labels, server)
                      .join(' · '),
                  selected: server == _currentServer,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _switchServer(server);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchServer(String server) async {
    final labels = _sourceLabels;
    final current =
        _currentQuality == null ? -1 : labels.indexOf(_currentQuality!);
    final target = VideoOptionGroups.switchTo(labels, current, server);
    if (target < 0 || target >= _videoSources.length) return;
    await _switchQuality(_videoSources[target]);
  }

  void _openSettingsSheet() {
    final hasServers = _sourceServers.length > 1;
    final hasQualities = _currentServerSources.length > 1;
    final langs = _availableLangsForCurrentEpisode();
    final hasLangs = langs.length > 1;
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
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'general.settings'.tr(),
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
              // Switching provider without losing your place.
              //
              // The app carries the same title on several ecosystems at once,
              // and until now the only way to leave a struggling source was to
              // back out and start the episode again somewhere else. Offered
              // here rather than only on the error screen, because a source
              // that is buffering badly has not failed yet — that is exactly
              // when someone wants out, and exactly when they have a position
              // worth keeping.
              //
              // Not for live: a channel is one stream, and there is no other
              // provider carrying the same minute of it.
              if (!_isLive)
                _SettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  label: 'player.change_source'.tr(),
                  value: widget.args.provider,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openAlternateSources(keepPosition: true);
                  },
                ),
              _SettingsTile(
                icon: Icons.speed_rounded,
                label: 'player.speed_short'.tr(),
                value:
                    '${_playbackSpeed.toStringAsFixed(_playbackSpeed == _playbackSpeed.roundToDouble() ? 0 : 2)}x',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSpeedSheet();
                },
              ),
              _SettingsTile(
                icon: Icons.aspect_ratio_rounded,
                label: 'player.aspect'.tr(),
                value: _fitLabel(_fit),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openFitSheet();
                },
              ),
              // Shown here, and not only in Settings, so a mode that suppresses
              // history cannot sit on unnoticed for weeks: the sheet is the one
              // surface a viewer opens mid-episode, and this is where they will
              // wonder why nothing is in Continue Watching.
              if (_hive.isIncognito)
                _SettingsTile(
                  icon: Icons.visibility_off_outlined,
                  label: 'profile.incognito'.tr(),
                  value: 'general.on'.tr(),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _hive.setIncognito(false);
                    if (!mounted) return;
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('profile.incognito_off'.tr()),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              // Hidden rather than disabled when the stream cannot be cast — a
              // torrent handle or a downloaded file has no address a device on
              // the network could fetch, and a greyed-out row invites a tap
              // that can only ever explain itself.
              if (_canCast)
                _SettingsTile(
                  icon: _cast.isCasting
                      ? Icons.cast_connected_rounded
                      : Icons.cast_rounded,
                  label: 'player.cast'.tr(),
                  value: _cast.device?.name ?? '—',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (_cast.isCasting) {
                      _stopCasting();
                    } else {
                      _openCastSheet();
                    }
                  },
                ),
              // Not offered for live TV: a broadcast has no end to stop at, and
              // a countdown that pauses a channel is just a mute button with
              // extra steps.
              if (!_isLive)
                _SettingsTile(
                  icon: Icons.bedtime_outlined,
                  label: 'player.sleep_timer'.tr(),
                  value: _sleepValueLabel,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openSleepSheet();
                  },
                ),
              if (hasServers)
                _SettingsTile(
                  icon: Icons.dns_outlined,
                  label: 'player.server'.tr(),
                  value: _currentServer ?? '—',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openServerSheet();
                  },
                ),
              if (hasQualities)
                _SettingsTile(
                  icon: Icons.high_quality_rounded,
                  label: 'player.quality'.tr(),
                  value: _currentQuality == null
                      ? '—'
                      : _qualityLabel(_currentQuality!),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openPanel(_SidePanel.quality);
                  },
                ),
              if (hasLangs)
                _SettingsTile(
                  icon: Icons.translate_rounded,
                  label: 'player.audio_language'.tr(),
                  value: _currentLang == null ? '—' : _langLabel(_currentLang!),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openLangSheet();
                  },
                ),
              _SettingsTile(
                icon: Icons.subtitles_outlined,
                label: 'player.subtitles'.tr(),
                value: _subtitles.isEmpty
                    ? 'general.search'.tr()
                    : _activeSubtitleIndex >= 0
                    ? _subtitles[_activeSubtitleIndex].label
                    : 'player.off'.tr(),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSubtitleSheet();
                },
              ),
              if (_subtitles.isNotEmpty)
                _SettingsTile(
                  icon: Icons.text_fields_rounded,
                  label: 'player.subtitle_style'.tr(),
                  value: '${_subtitleStyle.fontSize.round()}px',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openSubtitleAppearanceSheet();
                  },
                ),
              // Audio tracks are a media_kit capability: video_player exposes no
              // track-selection API at all. Under the default engine the tile
              // stays disabled and says why, rather than opening an empty sheet.
              if (!hasLangs)
                Builder(
                  builder: (_) {
                    final c = _controller;
                    final supported = c?.supportsAudioTracks ?? false;
                    final tracks = c?.audioTracks ?? const <PlayerAudioTrack>[];
                    if (!supported) {
                      return _SettingsTile(
                        icon: Icons.audiotrack_outlined,
                        label: 'player.audio_track'.tr(),
                        value: 'player.audio_track_engine_only'.tr(),
                        onTap: null,
                      );
                    }
                    return _SettingsTile(
                      icon: Icons.audiotrack_outlined,
                      label: 'player.audio_track'.tr(),
                      value: tracks.length < 2
                          ? 'player.audio_track_single'.tr()
                          : _activeAudioTrackLabel(),
                      onTap: tracks.length < 2
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              _openAudioTrackSheet();
                            },
                    );
                  },
                ),
              if (ExternalPlayer.isSupported && _videoUrl != null)
                _SettingsTile(
                  icon: Icons.open_in_new_rounded,
                  label: 'player.external_player'.tr(),
                  value: '',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _handOffToExternalPlayer();
                  },
                ),
              if (widget.args.showDownloadAction &&
                  widget.args.provider != 'uzmovi')
                _SettingsTile(
                  icon: Icons.download_rounded,
                  label: 'movie.download'.tr(),
                  value: '',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startDownload();
                  },
                ),
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                label: 'player.diagnostics_logs'.tr(),
                value: '',
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

  /// [PlayerAudioTrack.label] already resolves language codes to native names,
  /// but it cannot translate its own positional fallback — core has no
  /// business reaching for the locale. So do that one case here.
  String _audioTrackLabel(PlayerAudioTrack t) {
    if (t.hasMetadata) return t.label;
    return 'player.audio_track_numbered'
        .tr(args: <String>[t.ordinal.toString()]);
  }

  String _activeAudioTrackLabel() {
    final c = _controller;
    if (c == null) return '—';
    final active = c.activeAudioTrackId;
    for (final t in c.audioTracks) {
      if (t.id == active) return _audioTrackLabel(t);
    }
    return '—';
  }

  /// Audio-track picker. media_kit only — the caller already guarantees
  /// [PlayerController.supportsAudioTracks], so there is no empty state here.
  void _openAudioTrackSheet() {
    final c = _controller;
    if (c == null || !c.supportsAudioTracks) return;
    final tracks = c.audioTracks;
    if (tracks.length < 2) return;
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
                      Icons.audiotrack_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.audio_track'.tr(),
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
              for (final t in tracks)
                _OptionTile(
                  label: _audioTrackLabel(t),
                  selected: t.id == c.activeAudioTrackId,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _switchAudioTrack(t.id);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchAudioTrack(String id) async {
    final c = _controller;
    if (c == null) return;
    await c.setAudioTrack(id);
    if (mounted) setState(() {});
  }

  /// Hands the current stream to VLC / MX Player.
  ///
  /// Warns first when the stream is header-gated: an intent carries no
  /// Referer/Origin, so those sources 403 in the external app and present as a
  /// black screen. Better to say so than to launch into one.
  Future<void> _handOffToExternalPlayer() async {
    final url = _videoUrl;
    if (url == null || url.isEmpty) return;
    final headers = _headers;
    if (!ExternalPlayer.canHandOff(url, headers)) {
      final proceed = await showAdaptiveDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            'player.external_player'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'player.external_player_gated'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('general.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('player.external_player_try'.tr()),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    await _controller?.pause();
    final ok = await ExternalPlayer.open(
      url: url,
      title: widget.args.title,
      headers: headers,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('player.external_player_none'.tr())),
      );
    }
  }

  void _openSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
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
                    const Icon(Icons.speed_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'player.speed'.tr(),
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
                      Icons.aspect_ratio_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.aspect_ratio'.tr(),
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
    final sources = _currentServerSources;

    // Portrait phone: a full-height drawer over four quality rows covered the
    // video and matched nothing else in the player, where every other list —
    // speed, subtitles, servers, settings — arrives from the bottom. Landscape
    // and TV keep the drawer: there the height is the usable dimension.
    final asSheet = !isTvPlatform && !isDesktopPlatform && _isPortrait;

    final list = isQuality
        ? ListView.separated(
            controller: _tvPanelScroll,
            shrinkWrap: asSheet,
            padding: EdgeInsets.zero,
            itemCount: sources.length,
            separatorBuilder: (_, _) => Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
            ),
            itemBuilder: (_, i) {
              final src = _videoSources[sources[i]];
              return _QualityRow(
                source: _resolutionOnly(src),
                isActive: src.quality == _currentQuality,
                onTap: () => _switchQuality(src),
              );
            },
          )
        : ListView.separated(
            // Non-null only on TV (see _openPanel), where it opens
            // the list near the episode being watched.
            controller: _tvPanelScroll,
            shrinkWrap: asSheet,
            padding: EdgeInsets.zero,
            itemCount: widget.args.episodes.length,
            separatorBuilder: (_, _) => Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
            ),
            itemBuilder: (_, i) => _EpisodeRow(
              episode: widget.args.episodes[i],
              isActive: i == _episodeIndex,
              onTap: () => _partyEpisodeNav(i),
            ),
          );

    final body = Column(
      mainAxisSize: asSheet ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (asSheet)
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Text(
                isQuality ? 'player.quality'.tr() : 'player.episodes'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _closePanel,
                focusColor: _kTvFocusFill,
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        if (asSheet) Flexible(child: list) else Expanded(child: list),
      ],
    );

    final surface = Material(
      color: Colors.black.withValues(alpha: 0.92),
      shape: asSheet
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            )
          : null,
      child: SafeArea(
        // The panel hugs the right edge, so the left cutout inset is not its
        // to pay — honouring it just narrowed every row by ~44dp.
        left: false,
        top: !asSheet,
        // Its own focus scope so _openPanel can hand the remote over and
        // _closePanel can hand it back — see [_tvPanelFocus].
        child: FocusScope(node: _tvPanelFocus, child: body),
      ),
    );

    if (asSheet) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: surface,
        ),
      );
    }

    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      // Wider on TV: 320dp is a phone drawer, and at 10 feet the episode
      // labels in it truncate to uselessness.
      width: isTvPlatform ? 420 : 320,
      child: surface,
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.label,
    required this.qualities,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String qualities;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      autofocus: isTvPlatform && selected,
      focusColor: _kTvFocusFill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.primary : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (qualities.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      qualities,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
