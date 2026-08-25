// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Opening and ending skipping, backed by AniSkip.
///
/// Gated on the provider's own category rather than on whether a match came
/// back. AniSkip is keyed on MyAnimeList, and the id lookup falls back to a
/// title search — hand that an Uzbek film and it will occasionally find *some*
/// anime with a similar name and start offering to skip ninety seconds of it.
/// Asking the provider whether this is an anime source at all is one cheap
/// check that removes the entire class of false match.
///
/// The button is the default and auto-skip is opt-in. These times are
/// crowd-sourced: a wrong one that jumps the viewer into the middle of the
/// episode is a much worse first impression than a button they chose not to
/// press. Once someone trusts it, the setting is there.
extension _PlayerAniSkip on _PlayerPageState {
  /// How long the button stays offered after an interval starts.
  ///
  /// The interval itself can run 90 seconds, and a Skip button pinned over the
  /// video for that whole time is clutter long after the viewer has decided not
  /// to use it. Ten seconds is the window where the offer is useful.
  static const Duration _offerWindow = Duration(seconds: 10);

  bool get _aniSkipEligible =>
      _hive.providerCategory(widget.args.provider) == 'anime';

  /// Look up skip times for whatever is playing now.
  ///
  /// Called once the duration is known, because AniSkip uses episode length to
  /// reject submissions timed against a different cut.
  Future<void> _loadSkipTimes() async {
    if (!_aniSkipEligible || _isLive) return;
    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;

    final int episodeNumber;
    if (widget.args.isSerial) {
      if (_episodeIndex < 0 || _episodeIndex >= widget.args.episodes.length) {
        return;
      }
      episodeNumber = widget.args.episodes[_episodeIndex].episode;
    } else {
      // A film is episode 1 as far as AniSkip is concerned, the same way it is
      // for the trackers.
      episodeNumber = 1;
    }
    if (episodeNumber <= 0) return;

    final c = _controller;
    final length = c != null && c.value.isInitialized
        ? c.value.duration
        : Duration.zero;

    final intervals = await getIt<AniSkipService>().intervalsFor(
      provider: widget.args.provider,
      contentUrl: contentUrl,
      title: widget.args.title,
      episodeNumber: episodeNumber,
      episodeLength: length,
    );
    if (!mounted) return;
    setState(() {
      _skipIntervals = intervals;
      _activeSkip = null;
      _skipsTaken.clear();
    });
  }

  /// Clear per-episode state. Called when the episode changes.
  void _resetSkipTimes() {
    _skipIntervals = const [];
    _activeSkip = null;
    _skipsTaken.clear();
  }

  /// Decide whether a Skip offer belongs on screen at [position].
  ///
  /// Driven from the existing position listener rather than its own ticker:
  /// that listener already fires on every frame update the player receives, and
  /// a second timer would only be a second thing to keep in sync.
  void _updateActiveSkip(Duration position) {
    if (_skipIntervals.isEmpty) return;

    SkipInterval? active;
    for (final s in _skipIntervals) {
      if (!s.contains(position)) continue;
      // Already used, or declined by watching past the offer window.
      if (_skipsTaken.contains(s.type)) break;
      if (position - s.start > _PlayerAniSkip._offerWindow) break;
      active = s;
      break;
    }

    if (identical(active, _activeSkip)) return;
    if (active == null && _activeSkip == null) return;

    if (active != null && _hive.autoSkipIntro) {
      _takeSkip(active);
      return;
    }
    setState(() => _activeSkip = active);
  }

  /// Seek past [interval].
  ///
  /// Recorded in [_skipsTaken] so seeking back into the opening — to rewatch
  /// it, or because the viewer overshot — does not re-arm the same offer and,
  /// with auto-skip on, does not fight the viewer for control of the position.
  Future<void> _takeSkip(SkipInterval interval) async {
    _skipsTaken.add(interval.type);
    if (mounted) setState(() => _activeSkip = null);
    try {
      await _controller?.seekTo(interval.end);
    } catch (_) {
      // A failed seek leaves playback where it was, which is survivable; the
      // offer stays retired so it does not loop.
    }
  }

  /// The floating "Skip opening / Skip ending" button, or nothing.
  Widget _buildSkipButton() {
    final active = _activeSkip;
    if (active == null || !_controlsCanShowSkip) {
      return const SizedBox.shrink();
    }
    final label = active.type == 'ed'
        ? 'player.skip_ending'.tr()
        : 'player.skip_opening'.tr();
    return Positioned(
      right: 20,
      bottom: _controlsVisible ? 92 : 28,
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _takeSkip(active),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.fast_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Suppressed in the places a floating button would be wrong: picture-in-
  /// picture has no room for it, and a party guest skipping would desync the
  /// room rather than the episode.
  bool get _controlsCanShowSkip => !_isPip && !(_inParty && !_isPartyHost);
}
