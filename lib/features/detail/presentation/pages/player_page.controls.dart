// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerControls on _PlayerPageState {
  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _controlsAnimation.forward();
      _scheduleHide();
    } else {
      _controlsAnimation.reverse();
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final c = _controller;
      if (c != null && c.value.isPlaying && _panel == _SidePanel.none) {
        setState(() => _controlsVisible = false);
        _controlsAnimation.reverse();
      }
    });
  }

  void _togglePlay() {
    if (_partyBlockLocal()) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final wasPlaying = c.value.isPlaying;
    if (wasPlaying) {
      c.pause();
    } else {
      c.play();
      _scheduleHide();
    }
    _partyEmit(
      wasPlaying ? 'pause' : 'play',
      positionSec: c.value.position.inMilliseconds / 1000.0,
    );
  }

  void _setPlayerVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    setState(() => _volume = clamped);
    if (isDesktopPlatform) {
      _controller?.setVolume(clamped);
    } else {
      unawaited(_setSystemVolume(clamped));
    }
    _scheduleHide();
  }

  void _toggleMute() {
    if (_volume > 0.001) {
      _volumeBeforeMute = _volume;
      _setPlayerVolume(0);
    } else {
      _setPlayerVolume(_volumeBeforeMute <= 0.001 ? 1.0 : _volumeBeforeMute);
    }
  }

  void _seekRelative(Duration delta) {
    if (_partyBlockLocal()) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = c.value.position + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : next > c.value.duration
        ? c.value.duration
        : next;
    c.seekTo(clamped);
    _scheduleHide();
    if (!_isLive) {
      _partyEmit('seek', positionSec: clamped.inMilliseconds / 1000.0);
    }
  }

  void _seekTo(Duration position) {
    if (_partyBlockLocal()) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    c.seekTo(position);
    _scheduleHide();
    if (!_isLive) {
      _partyEmit('seek', positionSec: position.inMilliseconds / 1000.0);
    }
  }

  void _clearDragAfterSeek(Duration target) {
    void listener() {
      final c = _controller;
      if (c == null) {
        _sliderDragValue.value = null;
        return;
      }
      final diff = (c.value.position - target).inMilliseconds.abs();
      if (diff < 500) {
        c.removeListener(listener);
        _sliderDragValue.value = null;
      }
    }
    _controller?.addListener(listener);
    Future.delayed(const Duration(seconds: 1), () {
      _controller?.removeListener(listener);
      if (_sliderDragValue.value != null &&
          _sliderDragValue.value == target.inMilliseconds.toDouble()) {
        _sliderDragValue.value = null;
      }
    });
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  void _openPanel(_SidePanel panel) {
    setState(() {
      _panel = panel;
      _controlsVisible = true;
    });
    _controlsAnimation.forward();
    _hideTimer?.cancel();
  }

  void _closePanel() {
    setState(() => _panel = _SidePanel.none);
    _scheduleHide();
  }

  Future<void> _setSpeed(double speed) async {
    if (_partyBlockLocal()) return;
    setState(() => _playbackSpeed = speed);
    await _controller?.setPlaybackSpeed(speed);
    _partyEmit('rate', rate: speed);
  }

  void _setFit(_PlayerFit fit) {
    setState(() => _fit = fit);
  }

  String _fitLabel(_PlayerFit fit) {
    switch (fit) {
      case _PlayerFit.contain:
        return 'player.fit_original'.tr();
      case _PlayerFit.cover:
        return 'player.fit_fill'.tr();
      case _PlayerFit.fill:
        return 'player.fit_stretch'.tr();
    }
  }

  bool get _canGeneratePreview =>
      FramePreviewService.isSupported &&
      _isNetworkVideo &&
      _videoUrl != null &&
      (!_isHls || Platform.isIOS);

  Widget _buildVideoLayer() {
    if (_initializing) {
      return ColoredBox(
        color: Colors.black,
        child: _LoadingOverlay(stage: _stage, title: _episodeTitle()),
      );
    }
    final pluginCap = _pluginRequired;
    if (pluginCap != null) {
      // A party:content identity this device cannot resolve (missing on-device
      // plugin). Show the actionable install view — not a generic error — and
      // let the guest back out to the lobby to retry after installing.
      return ColoredBox(
        color: Colors.black,
        child: PartyPluginRequiredView(
          provider: _partyState.room?.content?.provider ?? widget.args.provider,
          installTarget: pluginCap.installTarget,
          onBack: () => Navigator.of(context).maybePop(),
        ),
      );
    }
    if (_errorMessage != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white70,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('general.try_again'.tr()),
                ),
                if (_isCodecError && _videoUrl != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      launchUrl(
                        Uri.parse(_videoUrl!),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: Text('player.play_in_browser'.tr()),
                  ),
                ],
                if (isCloudflareError(_errorMessage)) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await requestCloudflareSolve(
                        context,
                        widget.args.provider,
                      );
                      if (ok && mounted) _retry();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    label: Text('cloudflare.solve'.tr()),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => LogViewerSheet.show(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                  ),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: Text('player.view_logs'.tr()),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.black,
        child: _FittedVideo(controller: c, fit: _fit),
      ),
    );
  }

  Widget _buildSpeedBoostBadge() {
    return ValueListenableBuilder<bool>(
      valueListenable: _speedBoost,
      builder: (_, active, _) {
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          top: active ? 24 : -80,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: active ? 1 : 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'player.speed_2x'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScrubOverlay() {
    return ValueListenableBuilder<_ScrubState?>(
      valueListenable: _scrub,
      builder: (_, state, _) {
        if (state == null) return const SizedBox.shrink();
        final preview = state.previewPosition(_scrubSecondsPerFullSwipe);
        final deltaSeconds = (preview - state.baseline).inSeconds;
        final isForward = deltaSeconds >= 0;
        final thumb = _thumbnailAt(preview);
        return IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thumb != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildThumbnailImage(thumb),
                      ),
                    )
                  else if (_canGeneratePreview)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _GeneratedFramePreview(
                          url: _videoUrl!,
                          headers: _headers,
                          positionMs: preview.inMilliseconds,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isForward
                            ? Icons.fast_forward_rounded
                            : Icons.fast_rewind_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${isForward ? '+' : '−'}${deltaSeconds.abs()}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatDuration(preview)} / ${_formatDuration(state.duration)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnailImage(_VttThumbnail thumb) {
    const double displayWidth = 160;
    const double displayHeight = 90;

    if (thumb.hasSprite) {
      final sx = displayWidth / thumb.w;
      final sy = displayHeight / thumb.h;
      return SizedBox(
        width: displayWidth,
        height: displayHeight,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform(
              transform: Matrix4.diagonal3Values(sx, sy, 1.0)
                ..setTranslationRaw(
                    -thumb.x * sx, -thumb.y * sy, 0.0),
              child: Image.network(
                thumb.imageUrl,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => SizedBox(
                  width: displayWidth,
                  height: displayHeight,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Image.network(
      thumb.imageUrl,
      width: displayWidth,
      height: displayHeight,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox(
        width: displayWidth,
        height: displayHeight,
      ),
    );
  }

  Widget _buildSeekRipple() {
    if (_seekRippleDirection == 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: _seekRippleDirection < 0
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: AnimatedBuilder(
          animation: _seekRippleController,
          builder: (_, _) {
            final t = _seekRippleController.value;
            return Opacity(
              opacity: 1 - (t * 0.3),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _seekRippleDirection < 0
                          ? Icons.fast_rewind_rounded
                          : Icons.fast_forward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_seekRippleSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSwipeIndicator() {
    return ValueListenableBuilder<_SwipeIndicator?>(
      valueListenable: _swipeIndicator,
      builder: (_, indicator, _) {
        if (indicator == null) return const SizedBox.shrink();
        final isBrightness = indicator.type == _SwipeType.brightness;
        return Positioned(
          top: 0,
          bottom: 0,
          left: isBrightness ? 48 : null,
          right: isBrightness ? null : 48,
          child: Center(
            child: Container(
              width: 40,
              height: 140,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    isBrightness
                        ? Icons.brightness_6_rounded
                        : indicator.value > 0
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: indicator.value,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(indicator.value * 100).round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLockOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: GestureDetector(
              onTap: () => setState(() => _locked = false),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'player.tap_to_unlock'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    if (_isPip) return const SizedBox.shrink();
    final c = _controller;
    final initialized = c != null && c.value.isInitialized;
    final hasEpisodes = widget.args.isSerial && widget.args.episodes.isNotEmpty;
    final hasQualities = _videoSources.length > 1;
    final hasLangSwitcher = _availableLangsForCurrentEpisode().length > 1;
    final isBuffering = c != null && c.value.isBuffering;

    return FadeTransition(
      opacity: _controlsAnimation,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Stack(
          children: [
            const Positioned.fill(child: _ControlsScrim()),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _IconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: _exit,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _episodeTitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (hasLangSwitcher) ...[
                        _LangPill(
                          label: (_currentLang ?? _kSubLang).toUpperCase(),
                          onTap: _openLangSheet,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (!isDesktopPlatform) ...[
                        _IconButton(
                          icon: _isPortrait
                              ? Icons.screen_lock_landscape_rounded
                              : Icons.screen_lock_portrait_rounded,
                          onTap: _toggleOrientation,
                        ),
                        const SizedBox(width: 8),
                        _IconButton(
                          icon: Icons.lock_outline_rounded,
                          onTap: () => setState(() {
                            _locked = true;
                            _controlsVisible = false;
                            _controlsAnimation.reverse();
                            _hideTimer?.cancel();
                          }),
                        ),
                        const SizedBox(width: 8),
                        _IconButton(
                          icon: Icons.picture_in_picture_alt_rounded,
                          onTap: _enterPip,
                        ),
                        const SizedBox(width: 8),
                        _IconButton(
                          icon: Icons.settings_outlined,
                          onTap: _openSettingsSheet,
                        ),
                        const SizedBox(width: 8),
                        _IconButton(
                          icon: hasEpisodes
                              ? Icons.video_library_rounded
                              : Icons.high_quality_rounded,
                          onTap: hasEpisodes
                              ? () => _openPanel(_SidePanel.episodes)
                              : hasQualities
                                  ? () => _openPanel(_SidePanel.quality)
                                  : _openSettingsSheet,
                        ),
                      ],
                      if (isDesktopPlatform)
                        ValueListenableBuilder<bool>(
                          valueListenable: DesktopWindow.immersive,
                          builder: (_, imm, _) => imm
                              ? const WindowButtons()
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (initialized && !isBuffering && !isDesktopPlatform)
              _buildCenterPlayCluster(c),
            if (isBuffering)
              const Center(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.8,
                  ),
                ),
              ),
            if (initialized) _buildBottomBar(c, hasEpisodes, hasQualities),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPlayCluster(PlayerController c) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CenterIconButton(
            icon: Icons.replay_10_rounded,
            onTap: () {
              _seekRelative(const Duration(seconds: -10));
              _showSeekRipple(-1);
            },
          ),
          const SizedBox(width: 28),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, value, _) => _CenterIconButton(
              icon: value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onTap: _togglePlay,
              large: true,
            ),
          ),
          const SizedBox(width: 28),
          _CenterIconButton(
            icon: Icons.forward_10_rounded,
            onTap: () {
              _seekRelative(const Duration(seconds: 10));
              _showSeekRipple(1);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopControlRow(
    PlayerController c,
    bool hasEpisodes,
    bool hasQualities,
    bool hasPrev,
    bool hasNext,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _DesktopVolumeControl(
                volume: _volume,
                onChanged: _setPlayerVolume,
                onToggleMute: _toggleMute,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasEpisodes) ...[
                _IconButton(
                  icon: Icons.skip_previous_rounded,
                  onTap: () {
                    if (_episodeIndex - 1 >= 0) {
                      _partyEpisodeNav(_episodeIndex - 1);
                    }
                  },
                ),
                const SizedBox(width: 4),
              ],
              _IconButton(
                icon: Icons.replay_10_rounded,
                onTap: () {
                  _seekRelative(const Duration(seconds: -10));
                  _showSeekRipple(-1);
                },
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, value, _) => _IconButton(
                  icon: value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onTap: _togglePlay,
                ),
              ),
              const SizedBox(width: 6),
              _IconButton(
                icon: Icons.forward_10_rounded,
                onTap: () {
                  _seekRelative(const Duration(seconds: 10));
                  _showSeekRipple(1);
                },
              ),
              if (hasEpisodes) ...[
                const SizedBox(width: 4),
                _IconButton(
                  icon: Icons.skip_next_rounded,
                  onTap: () {
                    if (_episodeIndex + 1 < widget.args.episodes.length) {
                      _partyEpisodeNav(_episodeIndex + 1);
                    }
                  },
                ),
              ],
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BottomTextButton(
                      icon: Icons.speed_rounded,
                      label:
                          '${_playbackSpeed.toStringAsFixed(_playbackSpeed == _playbackSpeed.roundToDouble() ? 0 : 2)}x',
                      enabled: true,
                      onTap: _openSpeedSheet,
                    ),
                    _IconButton(
                      icon: Icons.subtitles_outlined,
                      onTap: _openSubtitleSheet,
                    ),
                    const SizedBox(width: 4),
                    _IconButton(
                      icon: Icons.settings_outlined,
                      onTap: _openSettingsSheet,
                    ),
                    if (hasQualities) ...[
                      const SizedBox(width: 4),
                      _IconButton(
                        icon: Icons.high_quality_rounded,
                        onTap: () => _openPanel(_SidePanel.quality),
                      ),
                    ],
                    if (hasEpisodes) ...[
                      const SizedBox(width: 4),
                      _IconButton(
                        icon: Icons.video_library_rounded,
                        onTap: () => _openPanel(_SidePanel.episodes),
                      ),
                    ],
                    const SizedBox(width: 4),
                    _IconButton(
                      icon: _isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      onTap: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    PlayerController c,
    bool hasEpisodes,
    bool hasQualities,
  ) {
    final hasNext =
        hasEpisodes && _episodeIndex + 1 < widget.args.episodes.length;
    final hasPrev = hasEpisodes && _episodeIndex - 1 >= 0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double?>(
                valueListenable: _sliderDragValue,
                builder: (_, dragVal, _) {
                  return ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, value, _) {
                      final duration = value.duration.inMilliseconds == 0
                          ? Duration.zero
                          : value.duration;
                      final maxMs = duration.inMilliseconds
                          .toDouble()
                          .clamp(1.0, double.infinity);
                      final sliderVal = dragVal ??
                          (duration.inMilliseconds == 0
                              ? 0.0
                              : value.position.inMilliseconds
                                    .clamp(0, duration.inMilliseconds)
                                    .toDouble());
                      final displayPos = dragVal != null
                          ? Duration(milliseconds: dragVal.toInt())
                          : value.position;

                      return LayoutBuilder(
                        builder: (context, constraints) {
                        const sliderPad = 24.0;
                        const thumbW = 160.0;
                        final trackWidth =
                            constraints.maxWidth - 80 - sliderPad * 2;
                        final fraction = maxMs > 0
                            ? (sliderVal / maxMs).clamp(0.0, 1.0)
                            : 0.0;
                        final thumbCenter =
                            40 + sliderPad + fraction * trackWidth;
                        final popupLeft = (thumbCenter - thumbW / 2)
                            .clamp(0.0, constraints.maxWidth - thumbW);

                        return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _isLive
                            ? [_buildLiveBar()]
                            : [
                          if (dragVal != null && (_hasThumbnails || _canGeneratePreview))
                            Builder(builder: (_) {
                              final thumb = _thumbnailAt(displayPos);
                              final Widget? img = thumb != null
                                  ? _buildThumbnailImage(thumb)
                                  : (_canGeneratePreview
                                      ? _GeneratedFramePreview(
                                          url: _videoUrl!,
                                          headers: _headers,
                                          positionMs: displayPos.inMilliseconds,
                                        )
                                      : null);
                              if (img == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: EdgeInsets.only(
                                    left: popupLeft, bottom: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        child: img,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDuration(displayPos),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          Row(
                            children: [
                              Text(
                                _formatDuration(displayPos),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 7,
                                    ),
                                    overlayShape:
                                        const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                    activeTrackColor: AppColors.primary,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                    overlayColor: AppColors.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                  child: Slider(
                                    value: sliderVal.clamp(0.0, maxMs),
                                    min: 0,
                                    max: maxMs,
                                    onChangeStart: (v) {
                                      _sliderDragValue.value = v;
                                      _hideTimer?.cancel();
                                    },
                                    onChanged: (v) {
                                      _sliderDragValue.value = v;
                                      _hideTimer?.cancel();
                                    },
                                    onChangeEnd: (v) {
                                      final target = Duration(
                                          milliseconds: v.toInt());
                                      _seekTo(target);
                                      _clearDragAfterSeek(target);
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 4),
              if (isDesktopPlatform)
                _buildDesktopControlRow(
                    c, hasEpisodes, hasQualities, hasPrev, hasNext)
              else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (hasEpisodes)
                      _BottomTextButton(
                        icon: Icons.skip_previous_rounded,
                        label: 'player.previous'.tr(),
                        enabled: hasPrev,
                        onTap: () => _partyEpisodeNav(_episodeIndex - 1),
                      ),
                    if (hasEpisodes)
                      _BottomTextButton(
                        icon: Icons.skip_next_rounded,
                        label: 'general.next'.tr(),
                        enabled: hasNext,
                        onTap: () => _partyEpisodeNav(_episodeIndex + 1),
                      ),
                    _BottomTextButton(
                      icon: Icons.speed_rounded,
                      label:
                          '${_playbackSpeed.toStringAsFixed(_playbackSpeed == _playbackSpeed.roundToDouble() ? 0 : 2)}x',
                      enabled: true,
                      onTap: _openSpeedSheet,
                    ),
                    if (hasQualities)
                      _BottomTextButton(
                        icon: Icons.high_quality_rounded,
                        label: _currentQuality ?? 'player.quality'.tr(),
                        enabled: true,
                        onTap: () => _openPanel(_SidePanel.quality),
                      ),
                    if (hasEpisodes)
                      _BottomTextButton(
                        icon: Icons.list_rounded,
                        label: 'player.episodes'.tr(),
                        enabled: true,
                        onTap: () => _openPanel(_SidePanel.episodes),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const _LiveDot(),
          const SizedBox(width: 7),
          Text(
            'player.live'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          _BottomTextButton(
            icon: Icons.fiber_manual_record_rounded,
            label: 'player.go_live'.tr(),
            enabled: true,
            onTap: () {
              final c = _controller;
              if (c == null || !c.value.isInitialized) return;
              final end = c.value.duration;
              if (end > Duration.zero) _seekTo(end);
              c.play();
            },
          ),
        ],
      ),
    );
  }
}
