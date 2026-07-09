// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Watch2Gether integration for the player.
///
/// Fields (`_applyingRemote`, the two timers, the two subscriptions,
/// `_lastPartyPlayback`, `_partyControlSnapshot`) live in `_PlayerPageState`
/// (player_page.dart) because Dart extensions cannot declare instance fields.
///
/// Invariants:
///  * A resolved stream URL is NEVER put on the wire — only identity fields.
///  * `_applyingRemote` guards against the sync feedback loop: while it is true
///    no `party:control` is emitted, so applying a remote sync never echoes back.
///  * Guests never self-advance episodes and never resolve peer URLs — every
///    device resolves its own stream from identity via [ResolveMediaUseCase].
extension _PlayerParty on _PlayerPageState {
  WatchPartyService get _party => getIt<WatchPartyService>();
  PartyState get _partyState => _party.state.value;
  bool get _inParty => _partyState.inParty;
  bool get _isPartyHost => _partyState.isHost;
  bool get _canPartyControl => _partyState.canControl;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void _partyInit() {
    if (!_inParty) return;
    // Seed the guest's drift target from the room snapshot so the first drift
    // correction can happen before the first `party:sync` arrives.
    final snapshot = _partyState.room?.playback;
    if (!_isPartyHost && snapshot != null) {
      _lastPartyPlayback = snapshot;
    }
    _partyControlSnapshot = _canPartyControl;
    _party.state.addListener(_onPartyStateChanged);
    _partySyncSub = _party.syncs.listen(_onPartySync);
    _partyContentSub = _party.contentChanges.listen(_onPartyContent);
    // Both timers run and self-guard by role, so host migration is handled
    // without tearing anything down.
    _partyHeartbeat = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _onHeartbeatTick(),
    );
    _partyDrift = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _onDriftTick(),
    );
  }

  void _partyDispose() {
    _partyHeartbeat?.cancel();
    _partyHeartbeat = null;
    _partyDrift?.cancel();
    _partyDrift = null;
    unawaited(_partySyncSub?.cancel());
    _partySyncSub = null;
    unawaited(_partyContentSub?.cancel());
    _partyContentSub = null;
    _party.state.removeListener(_onPartyStateChanged);
  }

  // ---------------------------------------------------------------------------
  // Incoming events
  // ---------------------------------------------------------------------------

  void _onPartyStateChanged() {
    if (!mounted) return;
    // Only rebuild when the control gate flips (e.g. host migration) to avoid a
    // rebuild storm from the frequent playback updates on the same notifier.
    final canControl = _canPartyControl;
    if (canControl != _partyControlSnapshot) {
      _partyControlSnapshot = canControl;
      setState(() {});
    }
  }

  void _onPartySync(PartyPlayback pb) {
    _lastPartyPlayback = pb;
    if (_inParty && !_isPartyHost) {
      unawaited(_applyRemoteSync(pb));
    }
  }

  void _onPartyContent(PartyContent content) {
    if (_inParty && !_isPartyHost) {
      unawaited(_applyRemoteContent(content));
    }
  }

  void _onHeartbeatTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_inParty && _isPartyHost && !_isLive) {
      _party.sendHeartbeat(c.value.position.inMilliseconds / 1000.0);
    }
  }

  void _onDriftTick() {
    final pb = _lastPartyPlayback;
    if (pb != null && _inParty && !_isPartyHost) {
      unawaited(_applyRemoteSync(pb));
    }
  }

  // ---------------------------------------------------------------------------
  // Control-surface gates
  // ---------------------------------------------------------------------------

  /// Blocks a local play/pause/seek/rate action (and toasts) when this device
  /// is in a party but not allowed to control it. Never blocks while a remote
  /// sync is being applied.
  bool _partyBlockLocal() {
    if (_inParty && !_canPartyControl && !_applyingRemote) {
      _partyToast('watch_party.only_host_controls');
      return true;
    }
    return false;
  }

  /// Episode navigation changes *what* is being watched, so it is host-only —
  /// even for a guest that would otherwise be allowed to control playback.
  bool _partyBlockEpisodeNav() {
    if (_inParty && !_isPartyHost && !_applyingRemote) {
      _partyToast('watch_party.only_host_controls');
      return true;
    }
    return false;
  }

  void _partyEpisodeNav(int index) {
    if (_partyBlockEpisodeNav()) return;
    _loadEpisode(index);
  }

  /// Emits a `party:control` — no-op unless we are in a party, allowed to
  /// control it, and not mid-apply of a remote sync (the feedback-loop guard).
  void _partyEmit(String action, {double? positionSec, double? rate}) {
    if (!_inParty || !_canPartyControl || _applyingRemote) return;
    _party.sendControl(action: action, positionSec: positionSec, rate: rate);
  }

  /// Host announces the identity of the episode it just loaded. Never carries a
  /// resolved video URL — the server would strip it anyway, and each guest
  /// resolves its own stream. No `season`/`server` exist in this app.
  void _partyEmitContent(EpisodeEntity ep, String? lang) {
    if (!_inParty || !_isPartyHost) return;
    _party.sendContent(
      PartyContent(
        provider: widget.args.provider,
        contentUrl: widget.args.contentUrl,
        mediaRef: ep.mediaRef,
        title: widget.args.title,
        thumbnail: widget.args.thumbnail,
        episode: ep.episode,
        lang: lang,
      ),
    );
  }

  void _partyToast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(key.tr()),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Applying remote state
  // ---------------------------------------------------------------------------

  Future<void> _applyRemoteSync(PartyPlayback pb) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_isLive) return; // live streams are unseekable
    if (_applyingRemote) return; // avoid overlapping applies
    _applyingRemote = true;
    try {
      final expected = pb.expectedPositionAt(DateTime.now());
      final actual = c.value.position.inMilliseconds / 1000.0;
      if ((actual - expected).abs() > 1.5) {
        await c.seekTo(Duration(milliseconds: (expected * 1000).round()));
      }
      if ((pb.rate - _playbackSpeed).abs() > 0.01) {
        _playbackSpeed = pb.rate;
        await c.setPlaybackSpeed(pb.rate);
      }
      if (pb.isPlaying) {
        await c.play();
      } else {
        await c.pause();
      }
    } finally {
      _applyingRemote = false;
    }
  }

  /// Guest side: a new content identity arrived. Re-resolve the stream ON THIS
  /// DEVICE (never reuse a peer's URL), then start playback aligned to the
  /// party's current position/rate.
  Future<void> _applyRemoteContent(PartyContent content) async {
    final ref = content.mediaRef;
    final provider = content.provider;
    if (ref == null || ref.isEmpty || provider == null || provider.isEmpty) {
      return;
    }

    final cap = await PartyResolveGate.canResolve(provider);
    if (!mounted) return;
    if (!cap.ok) {
      // This device cannot resolve the provider (missing plugin/extension).
      // Stop the old stream (otherwise its audio keeps playing behind the
      // overlay and the drift timer keeps driving it) and surface the same
      // actionable install view the lobby uses instead of a generic error with
      // a misleading "Try again" that would reload the previous title.
      await _disposeController();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorMessage = null;
        _isCodecError = false;
        _panel = _SidePanel.none;
        _pluginRequired = cap;
      });
      return;
    }

    setState(() {
      _initializing = true;
      _stage = _LoadingStage.resolving;
      _errorMessage = null;
      _isCodecError = false;
      _pluginRequired = null;
      _panel = _SidePanel.none;
    });
    await _disposeController();
    if (!mounted) return;

    final result = await _resolve(ref: ref, provider: provider, lang: content.lang);
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        final sources = value.videoSources;
        final useSources = sources.isNotEmpty;
        final url = useSources ? sources[0].videoUrl : value.videoUrl;
        setState(() {
          _stage = _LoadingStage.loading;
          _serverLangs = value.languagesAvailable;
          _currentLang = content.lang ?? value.activeLang ?? _currentLang;
          _videoSources = useSources ? List.of(sources) : const [];
          _currentSourceIndex = useSources ? 0 : -1;
          _currentQuality = useSources ? sources[0].quality : null;
          _autoFallbackUsed = false;
          _subtitles = value.subtitles;
          _activeSubtitleIndex = -1;
          _captionFile = null;
        });
        unawaited(_loadThumbnails(value.thumbnails));
        await _initializeWith(
          url: url,
          headers: value.headers,
          type: value.type,
          party: _lastPartyPlayback,
        );
        final subs = value.subtitles;
        if (subs.isNotEmpty) {
          final defaultIdx = subs.indexWhere((s) => s.isDefault);
          if (defaultIdx >= 0) _loadSubtitle(defaultIdx);
        }
      case Failure(:final error):
        setState(() {
          _initializing = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }
}
