// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerMedia on _PlayerPageState {
  String? _defaultRefererFor(String provider) {
    switch (provider.toLowerCase()) {
      case 'asilmedia':
        return 'https://asilmedia.org/';
      default:
        return null;
    }
  }

  bool _isHlsType(String? type) => type?.trim().toLowerCase() == 'hls';

  Future<void> _bootstrap() async {
    final resume = widget.args.resumePosition;
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex, resumeAt: resume);
    } else {
      _videoSources = List.of(widget.args.videoSources);
      _currentSourceIndex = _pickInitialMovieSourceIndex(_videoSources);
      _autoFallbackUsed = false;
      final source = _currentSourceIndex >= 0
          ? _videoSources[_currentSourceIndex]
          : null;
      _currentQuality = source?.quality;
      if (mounted) setState(() => _stage = _LoadingStage.loading);
      unawaited(_loadThumbnails(widget.args.thumbnails));
      await _initializeWith(
        url: source?.videoUrl ?? widget.args.movieUrl ?? '',
        headers: widget.args.headers,
        type: widget.args.type,
        resumeAt: resume,
      );
    }
  }

  int _pickInitialMovieSourceIndex(List<VideoSourceEntity> sources) {
    if (sources.isEmpty) return -1;
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].isDefault && sources[i].accessible) return i;
    }
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].accessible) return i;
    }
    return 0;
  }

  Future<void> _loadEpisode(
    int index, {
    Duration resumeAt = Duration.zero,
    bool keepRetryCount = false,
  }) async {
    if (index < 0 || index >= widget.args.episodes.length) return;
    if (!keepRetryCount) _retryAttempts = 0;
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
      _isCodecError = false;
      _episodeIndex = index;
      _panel = _SidePanel.none;
    });
    await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final ep = widget.args.episodes[index];
    if (ep.mediaRef.isEmpty) {
      setState(() {
        _initializing = false;
        _errorMessage = 'No source for this episode';
      });
      return;
    }

    final lang = _resolveLangForEpisode(ep);

    final resolveSw = Stopwatch()..start();
    final provider = widget.args.provider;
    _plog('resolving ref=${ep.mediaRef} lang=$lang');
    final result = await _resolve(
      ref: ep.mediaRef,
      provider: provider,
      lang: lang,
    );
    _plog('resolve completed in ${resolveSw.elapsedMilliseconds}ms');
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        final sources = value.videoSources;
        final useSources = sources.isNotEmpty;
        final pickedIdx = useSources ? 0 : -1;
        final url = useSources ? sources[pickedIdx].videoUrl : value.videoUrl;
        final subs = value.subtitles;
        setState(() {
          _stage = _LoadingStage.loading;
          _serverLangs = value.languagesAvailable;
          _currentLang = lang ?? value.activeLang ?? _currentLang;
          _videoSources = useSources ? List.of(sources) : const [];
          _currentSourceIndex = pickedIdx;
          _currentQuality = useSources ? sources[pickedIdx].quality : null;
          _autoFallbackUsed = false;
          _subtitles = subs;
          _activeSubtitleIndex = -1;
          _captionFile = null;
        });
        unawaited(_loadThumbnails(value.thumbnails));
        await _initializeWith(
          url: url,
          headers: value.headers,
          type: value.type,
          resumeAt: resumeAt,
        );
        if (subs.isNotEmpty) {
          final defaultIdx = subs.indexWhere((s) => s.isDefault);
          if (defaultIdx >= 0) {
            _loadSubtitle(defaultIdx);
          }
        }
      case Failure(:final error):
        setState(() {
          _initializing = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  String? _resolveLangForEpisode(EpisodeEntity ep) {
    final epLangs = ep.availableLangs;
    if (epLangs.isEmpty) return null;
    final saved = _currentLang;
    if (saved != null && epLangs.contains(saved)) return saved;
    if (epLangs.contains(_kSubLang)) return _kSubLang;
    return epLangs.first;
  }

  List<String> _availableLangsForCurrentEpisode() {
    if (!widget.args.isSerial) return const [];
    if (_episodeIndex < 0 || _episodeIndex >= widget.args.episodes.length) {
      return const [];
    }
    final epLangs = widget.args.episodes[_episodeIndex].availableLangs;
    if (epLangs.isNotEmpty) return epLangs;
    return _serverLangs;
  }

  Future<void> _switchLang(String lang) async {
    if (!widget.args.isSerial) return;
    if (lang == _currentLang) return;
    final keepPosition = _controller?.value.position ?? Duration.zero;
    setState(() => _currentLang = lang);
    await _hive.savePreferredMediaLang(lang);
    await _loadEpisode(_episodeIndex, resumeAt: keepPosition);
  }

  Future<void> _switchQuality(VideoSourceEntity source) async {
    if (source.quality == _currentQuality) {
      setState(() => _panel = _SidePanel.none);
      return;
    }
    final keepPosition = _controller?.value.position ?? Duration.zero;
    final idx = _videoSources.indexWhere((s) => s.quality == source.quality);
    _retryAttempts = 0;
    setState(() {
      _initializing = true;
      _stage = _LoadingStage.loading;
      _errorMessage = null;
      _isCodecError = false;
      _currentQuality = source.quality;
      _currentSourceIndex = idx >= 0 ? idx : _currentSourceIndex;
      _autoFallbackUsed = false;
      _panel = _SidePanel.none;
    });
    await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await _initializeWith(
      url: source.videoUrl,
      headers: _headers.isNotEmpty ? _headers : widget.args.headers,
      type: _mediaType,
      resumeAt: keepPosition,
    );
  }

  Future<_ProxiedTarget?> _maybeRouteThroughLocalProxy({
    required String url,
    required Map<String, String> headers,
  }) async {
    if (_currentSourceIndex < 0 ||
        _currentSourceIndex >= _videoSources.length) {
      return null;
    }
    final source = _videoSources[_currentSourceIndex];
    if (!source.useLocalProxy) return null;
    if (source.videoUrl != url) return null;
    final upstreamHeaders = source.headers.isNotEmpty ? source.headers : headers;
    try {
      final proxied = await getIt<LocalHlsProxy>().register(
        upstreamUrl: url,
        headers: upstreamHeaders,
        localProxy: source.localProxy,
        requestTransform: source.requestTransform,
      );
      _plog('routing through local HLS proxy: $proxied');
      return _ProxiedTarget(url: proxied, headers: const {});
    } catch (e) {
      _plog('local proxy register failed: $e — using direct url',
          level: LogLevel.warn);
      return null;
    }
  }

  Future<void> _initializeWith({
    required String url,
    required Map<String, String> headers,
    required String? type,
    Duration resumeAt = Duration.zero,
  }) async {
    if (url.isEmpty) {
      setState(() {
        _initializing = false;
        _errorMessage = 'Empty video URL';
      });
      return;
    }

    final stopwatch = Stopwatch()..start();
    final isFileUri = url.startsWith('file://');
    final isLocal = url.startsWith('/') || isFileUri;
    final isHls = _isHlsType(type) || url.toLowerCase().contains('.m3u8');
    final isDash = type?.trim().toLowerCase() == 'dash' ||
        url.toLowerCase().contains('.mpd');
    _isHls = isHls;

    final proxied = !isLocal && isHls
        ? await _maybeRouteThroughLocalProxy(url: url, headers: headers)
        : null;
    final effectiveUrl = proxied?.url ?? url;
    final effectiveHeaders = proxied?.headers ?? headers;

    final fmt = isHls
        ? 'hls'
        : isDash
            ? 'dash'
            : (type ?? 'progressive');
    PlayerLog.instance.setContext({
      'url': effectiveUrl,
      'type': fmt,
      'local': isLocal.toString(),
      'quality': _currentQuality,
    });
    _plog('loading url: $effectiveUrl');
    _plog('type: $fmt (raw=${type ?? 'unknown'}) local: $isLocal');

    PlayerController controller;
    if (isLocal && isHls) {
      final fileUri = isFileUri ? Uri.parse(effectiveUrl) : Uri.file(effectiveUrl);
      controller = PlayerController.networkUrl(
        fileUri,
        formatHint: VideoFormat.hls,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
      _headers = const {};
    } else if (isLocal) {
      final file = isFileUri
          ? File(Uri.parse(effectiveUrl).toFilePath())
          : File(effectiveUrl);
      controller = PlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
      _headers = const {};
    } else {
      final uri = Uri.parse(effectiveUrl);
      final isLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
      final mergedHeaders = <String, String>{};
      if (!isLoopback) {
        mergedHeaders.addAll(<String, String>{
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
          'Accept-Language': 'uz,ru;q=0.9,en;q=0.8',
        });
        final defaultReferer = _defaultRefererFor(widget.args.provider);
        if (defaultReferer != null) mergedHeaders['Referer'] = defaultReferer;
        mergedHeaders.addAll(effectiveHeaders);
      }

      _plog('provider: ${widget.args.provider}');
      _plog('headers (${mergedHeaders.length}):');
      mergedHeaders.forEach((k, v) {
        _plog('  $k: $v');
      });

      controller = PlayerController.networkUrl(
        uri,
        httpHeaders: mergedHeaders,
        formatHint: isHls
            ? VideoFormat.hls
            : isDash
                ? VideoFormat.dash
                : null,
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: false,
        ),
      );
      _headers = mergedHeaders;
    }
    _controller = controller;
    _videoUrl = effectiveUrl;
    _mediaType = type;
    _isNetworkVideo = !isLocal;

    try {
      await controller.initialize();
      _plog('initialize completed in ${stopwatch.elapsedMilliseconds}ms');
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (controller.value.hasError) {
        final raw = controller.value.errorDescription;
        _plog('init error: $raw', level: LogLevel.error);
        setState(() {
          _initializing = false;
          _errorMessage = raw == null
              ? 'Could not load video'
              : _humanizeError(raw);
        });
        return;
      }
      // Live / IPTV detection: a live HLS has no real duration (it's a sliding
      // window), so video_player reports zero or an absurd length. When live we
      // skip resume-seeking and generated previews, which don't apply.
      final dur = controller.value.duration;
      _isLive = dur <= Duration.zero || dur.inHours >= 12;
      PlayerLog.instance.setContext({
        'live': _isLive.toString(),
        'duration': _isLive ? 'live' : dur.toString(),
      });
      _plog('initialized — ${_isLive ? 'LIVE stream' : 'duration $dur'}');
      // Warm the seek-preview generator so the very first scrub already has a
      // frame ready. `_canGeneratePreview` already encodes the platform/HLS
      // rules (Android skips HLS, iOS allows it). Live has no seekable window.
      if (_canGeneratePreview && !_isLive) {
        // Warm at the resume position (or start) so the first scrub there is
        // already decoded instead of cold-starting the codec on first drag.
        FramePreviewService.open(
          _videoUrl!,
          _headers,
          warmMs: resumeAt.inMilliseconds,
        );
      }
      controller.addListener(_onMajorChange);
      await controller.setLooping(false);
      await controller.setPlaybackSpeed(_playbackSpeed);
      if (resumeAt > Duration.zero && !_isLive) {
        await controller.seekTo(resumeAt);
      }
      await controller.play();
      _plog('play started — total ${stopwatch.elapsedMilliseconds}ms');
      setState(() {
        _initializing = false;
        _errorMessage = null;
      _isCodecError = false;
      });
      _scheduleHide();
    } on PlatformException catch (e) {
      _plog('platform exception ${e.code}: ${e.message}',
          level: LogLevel.error);
      if (!mounted) return;
      final raw = e.message ?? '';
      String msg;
      if (e.code == 'channel-error') {
        msg = 'Player not ready — please fully restart the app';
      } else if (raw.contains('Cannot Decode') ||
          raw.contains('-12906') ||
          raw.contains('-12939') ||
          raw.contains('CoreMediaError')) {
        if (!_autoFallbackUsed && _videoSources.length > 1) {
          _autoRetrying = true;
          _autoRetry();
          return;
        }
        _isCodecError = true;
        msg =
            'This video format is not supported on your device. You can try playing it in your browser.';
      } else if (_isRecoverableError(raw) && _retryAttempts < 2) {
        _plog('recoverable error, retrying (attempt ${_retryAttempts + 1})',
            level: LogLevel.warn);
        _retryAttempts++;
        _autoRetrying = true;
        _autoRetry();
        return;
      } else {
        msg = raw.isEmpty ? 'Could not load video' : _humanizeError(raw);
      }
      setState(() {
        _initializing = false;
        _errorMessage = msg;
      });
    } catch (e) {
      _plog('init threw: $e', level: LogLevel.error);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _humanizeError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('mediacodec') ||
        lower.contains('decoder') ||
        lower.contains('renderer')) {
      return 'This device couldn\'t decode the video. Try a different quality or retry.';
    }
    if (lower.contains('source error') ||
        lower.contains('unrecognizedinputformat') ||
        lower.contains('nodeclaredbrand')) {
      return 'Couldn\'t open the video source (the server may have blocked it). Try a different quality.';
    }
    if (lower.contains('http data source')) {
      return 'Network error — check your connection';
    }
    if (lower.contains('cannot decode') ||
        lower.contains('-12906') ||
        lower.contains('coremediaerror')) {
      return 'This video format is not supported on your device. Try a different quality.';
    }
    return raw;
  }

  bool _isRecoverableError(String msg) {
    final l = msg.toLowerCase();
    // Never retry format/config/404 errors — these will always fail
    if (l.contains('-12939') ||
        l.contains('-12938') ||
        l.contains('-12660') ||
        l.contains('404') ||
        l.contains('403') ||
        l.contains('not found') ||
        l.contains('forbidden') ||
        l.contains('coremediaerror') ||
        l.contains('cannot decode') ||
        l.contains('-12906')) {
      return false;
    }
    return l.contains('timed out') ||
        l.contains('timeout') ||
        l.contains('-1001') ||
        l.contains('-1005') ||
        l.contains('source error') ||
        l.contains('mediacodec') ||
        l.contains('decoder') ||
        l.contains('renderer');
  }

  void _onMajorChange() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;

    if (v.hasError) {
      final msg = v.errorDescription;
      if (msg != null && msg != _lastError && mounted) {
        _lastError = msg;
        _plog('playback error: $msg', level: LogLevel.error);
        if (!_autoRetrying && _retryAttempts < 2 && _isRecoverableError(msg)) {
          _retryAttempts++;
          _autoRetrying = true;
          _autoRetry();
          return;
        }
        setState(() => _errorMessage = _humanizeError(msg));
      }
      return;
    }
    if (v.isInitialized) {
      _retryAttempts = 0;
      _autoRetrying = false;
    }

    var changed = false;
    if (v.isInitialized != _wasInitialized) {
      _wasInitialized = v.isInitialized;
      changed = true;
    }
    if (v.isPlaying != _wasPlaying) {
      _wasPlaying = v.isPlaying;
      changed = true;
      if (_isPip) _refreshPipActions();
      if (v.isPlaying) {
        _playbackWatch.start();
        _scheduleHistorySave();
      } else {
        _playbackWatch.stop();
        _saveHistory();
      }
    }
    if (!_streakPingScheduled && _playbackWatch.elapsed.inSeconds >= 60) {
      _streakPingScheduled = true;
      _pingStreak();
    }
    if (v.isBuffering != _wasBuffering) {
      _wasBuffering = v.isBuffering;
      changed = true;
    }

    if (v.isInitialized && v.duration.inMilliseconds > 0) {
      final remaining = v.duration - v.position;
      final isEnding = remaining <= const Duration(seconds: 2);
      if (isEnding) {
        if (widget.args.isSerial &&
            _episodeIndex + 1 < widget.args.episodes.length) {
          _saveHistoryForNextEpisode();
          _loadEpisode(_episodeIndex + 1);
          return;
        }
        final url = widget.args.contentUrl;
        if (url != null && url.isNotEmpty) {
          _history.remove(url);
        }
      }
    }

    if (changed && mounted) setState(() {});
  }

  Future<void> _autoRetry() async {
    if (!mounted) return;

    if (!_autoFallbackUsed &&
        _videoSources.length > 1 &&
        _currentSourceIndex >= 0 &&
        _currentSourceIndex + 1 < _videoSources.length) {
      final nextIdx = _currentSourceIndex + 1;
      final next = _videoSources[nextIdx];
      _autoFallbackUsed = true;
      setState(() {
        _initializing = true;
        _stage = _LoadingStage.loading;
        _errorMessage = null;
      _isCodecError = false;
        _currentSourceIndex = nextIdx;
        _currentQuality = next.quality;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switching to ${next.quality}...'),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _disposeController();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await _initializeWith(
        url: next.videoUrl,
        headers: _headers.isNotEmpty ? _headers : widget.args.headers,
        type: _mediaType,
      );
      _autoRetrying = false;
      return;
    }

    setState(() {
      _initializing = true;
      _stage = widget.args.isSerial
          ? _LoadingStage.resolving
          : _LoadingStage.loading;
      _errorMessage = null;
      _isCodecError = false;
    });
    await _disposeController();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex, keepRetryCount: true);
    } else if (_videoUrl != null) {
      await _initializeWith(
        url: _videoUrl!,
        headers: _headers,
        type: _mediaType,
      );
    } else {
      await _bootstrap();
    }
    _autoRetrying = false;
  }

  Future<void> _disposeController() async {
    _hideTimer?.cancel();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onMajorChange);
      try {
        await c.pause();
      } catch (_) {}
      await c.dispose();
    }
    _controller = null;
    _wasPlaying = false;
    _wasBuffering = false;
    _wasInitialized = false;
    _lastError = null;
  }

  String _episodeTitle() {
    if (!widget.args.isSerial) return widget.args.title;
    final ep = widget.args.episodes[_episodeIndex];
    final fallback = 'Episode ${ep.episode}';
    final label = ep.label.trim().isEmpty ? fallback : ep.label;
    return '${widget.args.title} · $label';
  }

  Future<void> _retry() async {
    if (widget.args.isSerial) {
      await _loadEpisode(_episodeIndex);
    } else if (_videoUrl != null) {
      setState(() {
        _initializing = true;
        _stage = _LoadingStage.loading;
        _errorMessage = null;
      _isCodecError = false;
      });
      await _disposeController();
      await _initializeWith(
        url: _videoUrl!,
        headers: _headers,
        type: _mediaType,
      );
    }
  }

  Future<void> _loadThumbnails(ThumbnailsEntity? thumbnails) async {
    if (thumbnails == null) {
      _thumbnailsKey = null;
      _vttThumbnails = const [];
      _storyboard = null;
      return;
    }
    if (thumbnails.isStoryboard) {
      final key = 'sb:${thumbnails.template}';
      if (key == _thumbnailsKey && _storyboard != null) return;
      _thumbnailsKey = key;
      _vttThumbnails = const [];
      _storyboard = thumbnails;
      return;
    }
    if (!thumbnails.isVtt) {
      _thumbnailsKey = null;
      _vttThumbnails = const [];
      _storyboard = null;
      return;
    }
    final url = thumbnails.url!;
    final key = 'vtt:$url';
    if (key == _thumbnailsKey && _vttThumbnails.isNotEmpty) return;
    _thumbnailsKey = key;
    _storyboard = null;
    try {
      final response = await Dio().get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: thumbnails.headers.isEmpty ? null : thumbnails.headers,
        ),
      );
      if (!mounted) return;
      final body = response.data;
      if (body != null && body.isNotEmpty) {
        _vttThumbnails = _VttThumbnail.parse(body, url);
        _plog('loaded ${_vttThumbnails.length} VTT thumbnails');
      }
    } catch (e) {
      _plog('VTT thumbnails load error: $e', level: LogLevel.warn);
      _vttThumbnails = const [];
    }
  }

  bool get _hasThumbnails =>
      _vttThumbnails.isNotEmpty || _storyboard != null;

  _VttThumbnail? _thumbnailAt(Duration position) {
    final sb = _storyboard;
    if (sb != null && sb.isStoryboard) {
      final c = _controller;
      final durMs = c != null && c.value.isInitialized
          ? c.value.duration.inMilliseconds
          : 0;
      if (durMs <= 0) return null;
      final cols = sb.columns!;
      final rows = sb.rows!;
      final totalCells = cols * rows;
      final ratio = position.inMilliseconds / durMs;
      final idx = (ratio * totalCells)
          .clamp(0, totalCells - 1)
          .floor();
      final col = idx % cols;
      final row = idx ~/ cols;
      final cellW = (sb.width! / cols).round();
      final cellH = (sb.height! / rows).round();
      return _VttThumbnail(
        start: Duration.zero,
        end: Duration.zero,
        imageUrl: sb.template!,
        x: col * cellW,
        y: row * cellH,
        w: cellW,
        h: cellH,
      );
    }
    for (final t in _vttThumbnails) {
      if (t.contains(position)) return t;
    }
    return null;
  }
}
