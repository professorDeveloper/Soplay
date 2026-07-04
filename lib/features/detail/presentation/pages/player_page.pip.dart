// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerPip on _PlayerPageState {
  Future<void> _loadSystemControlValues() async {
    try {
      final results = await Future.wait([
        _systemControlsChannel.invokeMethod<double>('getBrightness'),
        _systemControlsChannel.invokeMethod<double>('getVolume'),
      ]);
      _brightness = (results[0] ?? _brightness).clamp(0.0, 1.0).toDouble();
      _volume = (results[1] ?? _volume).clamp(0.0, 1.0).toDouble();
    } catch (_) {}
  }

  Future<void> _onPipMethodCall(MethodCall call) async {
    if (call.method != 'onPipAction') return;
    final action = call.arguments;
    if (action is! String) return;
    switch (action) {
      case 'play_pause':
        _togglePlay();
        _refreshPipActions();
      case 'rewind':
        _seekRelative(const Duration(seconds: -10));
      case 'forward':
        _seekRelative(const Duration(seconds: 10));
      case 'prev':
        if (widget.args.isSerial && _episodeIndex - 1 >= 0) {
          _loadEpisode(_episodeIndex - 1);
        }
      case 'next':
        if (widget.args.isSerial &&
            _episodeIndex + 1 < widget.args.episodes.length) {
          _loadEpisode(_episodeIndex + 1);
        }
    }
  }

  Future<void> _refreshPipActions() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final isPlaying = c.value.isPlaying;
    final hasPrev = widget.args.isSerial && _episodeIndex > 0;
    final hasNext =
        widget.args.isSerial && _episodeIndex + 1 < widget.args.episodes.length;
    if (isPlaying == _lastPipPlaying) {
      try {
        await _pipChannel.invokeMethod('updatePiPActions', {
          'isPlaying': isPlaying,
          'hasPrev': hasPrev,
          'hasNext': hasNext,
        });
      } catch (_) {}
      return;
    }
    _lastPipPlaying = isPlaying;
    try {
      await _pipChannel.invokeMethod('updatePiPActions', {
        'isPlaying': isPlaying,
        'hasPrev': hasPrev,
        'hasNext': hasNext,
      });
    } catch (_) {}
  }

  Future<void> _enterPip() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      final available = await _floating.isPipAvailable;
      if (!available) return;
      final size = c.value.size;
      Rational ratio = const Rational.landscape();
      if (size.width > 0 && size.height > 0) {
        final w = size.width.round();
        final h = size.height.round();
        if (w > 0 && h > 0) {
          final candidate = Rational(w, h);
          final aspect = candidate.aspectRatio;
          if (aspect >= 1 / 2.39 && aspect <= 2.39) {
            ratio = candidate;
          }
        }
      }
      final result = await _floating.enable(ImmediatePiP(aspectRatio: ratio));
      if (result == PiPStatus.enabled && mounted) {
        setState(() {
          _isPip = true;
          _controlsVisible = false;
          _hideTimer?.cancel();
          _panel = _SidePanel.none;
        });
        _controlsAnimation.reverse();
        _lastPipPlaying = !c.value.isPlaying;
        _refreshPipActions();
      }
    } catch (_) {}
  }

  Future<void> _startup() async {
    final sw = Stopwatch()..start();
    _plog('startup — entering fullscreen');
    await _enterFullscreen();
    _plog('fullscreen ready in ${sw.elapsedMilliseconds}ms');
    if (!mounted) return;
    await _bootstrap();
  }

  Future<void> _enterFullscreen() async {
    // Desktop doesn't auto-enter OS fullscreen (that's jarring on a windowed
    // desktop); the user toggles it with the button / F key.
    if (isDesktopPlatform) {
      await WakelockPlus.enable();
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      await AppOrientation.set([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
    await WakelockPlus.enable();
  }

  /// Desktop: true OS-window fullscreen (hides the taskbar), toggled by the
  /// fullscreen button or the F key. No-op on mobile (uses immersive mode).
  Future<void> _toggleFullscreen() async {
    if (!isDesktopPlatform) return;
    final next = !_isFullscreen;
    try {
      await windowManager.setFullScreen(next);
    } catch (_) {}
    if (mounted) setState(() => _isFullscreen = next);
  }

  Future<void> _toggleOrientation() async {
    _isPortrait = !_isPortrait;
    try {
      if (_isPortrait) {
        await AppOrientation.set([
          DeviceOrientation.portraitUp,
        ]);
      } else {
        await AppOrientation.set([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } catch (_) {}
    setState(() {});
  }

  Future<void> _restoreSystemUi() async {
    _isPortrait = false;
    if (isDesktopPlatform) {
      // Leave OS fullscreen so the app isn't stuck fullscreen after the player.
      try {
        if (_isFullscreen) {
          await windowManager.setFullScreen(false);
          _isFullscreen = false;
        }
      } catch (_) {}
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      return;
    }
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      await AppOrientation.set([
        DeviceOrientation.portraitUp,
      ]);
    } catch (_) {}
    await WakelockPlus.disable();
  }

  Future<void> _setSystemBrightness(double value) async {
    try {
      await _systemControlsChannel.invokeMethod<double>('setBrightness', {
        'value': value,
      });
    } catch (_) {}
  }

  Future<void> _setSystemVolume(double value) async {
    try {
      await _systemControlsChannel.invokeMethod<double>('setVolume', {
        'value': value,
      });
    } catch (_) {}
  }
}
