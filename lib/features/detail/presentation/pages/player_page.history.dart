part of 'player_page.dart';

/// How far through an episode counts as "watched" for tracking purposes.
///
/// 85% is the convention every anime tracker uses, and it exists because
/// endings and next-episode previews are routinely skipped.
const double _kTrackerThreshold = 0.85;

extension _PlayerHistory on _PlayerPageState {
  void _scheduleHistorySave() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(seconds: 5), _saveHistory);
  }

  void _saveHistory() {
    if (_playbackWatch.elapsed.inSeconds < 10) return;

    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;
    final c = _controller;
    final posMs = c != null && c.value.isInitialized
        ? c.value.position.inMilliseconds
        : 0;
    final durMs = c != null && c.value.isInitialized
        ? c.value.duration.inMilliseconds
        : 0;

    if (durMs > 0 && posMs >= durMs - 2000) return;

    EpisodeEntity? ep;
    if (widget.args.isSerial &&
        _episodeIndex >= 0 &&
        _episodeIndex < widget.args.episodes.length) {
      ep = widget.args.episodes[_episodeIndex];
    }

    _history.save(
      HistoryItem(
        contentUrl: contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        thumbnail: widget.args.thumbnail,
        isSerial: widget.args.isSerial,
        episodeIndex: widget.args.isSerial ? _episodeIndex : null,
        episodeNumber: ep?.episode,
        episodeLabel: ep?.label,
        positionMs: posMs,
        durationMs: durMs,
        watchedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _saveHistoryForNextEpisode() {
    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;
    if (!widget.args.isSerial) return;

    final nextIdx = _episodeIndex + 1;
    if (nextIdx >= widget.args.episodes.length) return;

    final nextEp = widget.args.episodes[nextIdx];
    _history.save(
      HistoryItem(
        contentUrl: contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        thumbnail: widget.args.thumbnail,
        isSerial: true,
        episodeIndex: nextIdx,
        episodeNumber: nextEp.episode,
        episodeLabel: nextEp.label,
        positionMs: 0,
        durationMs: 0,
        watchedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Reports the episode in progress to every connected tracker once it is far
  /// enough through.
  ///
  /// Fires at [_kTrackerThreshold] rather than at the very end because a viewer
  /// who skips the ending, or who closes the player on the credits, has still
  /// watched the episode — waiting for the last frame loses those entirely.
  ///
  /// Everything about this is fire-and-forget: no await on the caller's path,
  /// no snackbar, no error state. It runs during playback, and a tracker being
  /// down is not the viewer's problem to see.
  ///
  /// The guard set is shared across trackers rather than kept per tracker. One
  /// episode is one event; a MAL write that fails must not be retried by the
  /// next tick, which is exactly what a per-tracker set would cause.
  void _maybeReportTrackers() {
    // Incognito covers the trackers too. Suppressing local history while still
    // pushing the episode to AniList and MAL would leave the record in the one
    // place the viewer cannot quietly clear — someone else's server.
    if (_hive.isIncognito) return;

    final contentUrl = widget.args.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;

    final anilist = getIt<AnilistTracker>();
    final mal = getIt<MalTracker>();
    if (!anilist.isConnected && !mal.isConnected) return;

    // A movie is one episode as far as a tracker is concerned.
    final int episodeNumber;
    if (widget.args.isSerial) {
      if (_episodeIndex < 0 || _episodeIndex >= widget.args.episodes.length) {
        return;
      }
      episodeNumber = widget.args.episodes[_episodeIndex].episode;
    } else {
      episodeNumber = 1;
    }
    if (episodeNumber <= 0 || !_trackersReported.add(episodeNumber)) return;

    for (final tracker in <Future<int?> Function()>[
      if (anilist.isConnected)
        () => anilist.reportEpisode(
              provider: widget.args.provider,
              contentUrl: contentUrl,
              title: widget.args.title,
              episodeNumber: episodeNumber,
            ),
      if (mal.isConnected)
        () => mal.reportEpisode(
              provider: widget.args.provider,
              contentUrl: contentUrl,
              title: widget.args.title,
              episodeNumber: episodeNumber,
            ),
    ]) {
      unawaited(tracker().catchError((Object _) => null));
    }
  }

  Future<void> _pingStreak() async {
    try {
      final result = await getIt<StreakService>().ping();
      if (result == null || !mounted) return;
      final milestone = result.newMilestone;
      if (milestone != null) {
        await StreakMilestoneDialog.show(
          context,
          milestone,
          freezeAwarded: result.freezeAwarded,
        );
      }
      // Independent of the milestone: a ping can both cross a milestone AND
      // consume a banked freeze to rescue a missed day. Surface the freeze
      // rescue too (re-checking mounted after the milestone dialog's await).
      if (result.freezeSaved && mounted) {
        await StreakFreezeSavedDialog.show(context);
      }
    } catch (_) {}
  }

  Future<void> _startDownload() async {
    final url = _videoUrl;
    if (url == null || url.isEmpty) return;

    EpisodeEntity? ep;
    if (widget.args.isSerial &&
        _episodeIndex >= 0 &&
        _episodeIndex < widget.args.episodes.length) {
      ep = widget.args.episodes[_episodeIndex];
    }

    // Shared with the episode list so both screens address the same download.
    final id = DownloadService.videoId(
      contentUrl: widget.args.contentUrl ?? url,
      episodeNumber: widget.args.isSerial && ep != null ? ep.episode : null,
    );

    final existing = _downloads.get(id);
    if (existing != null) {
      if (existing.status == DownloadStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('detail.download_already'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (existing.status == DownloadStatus.downloading) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('detail.download_in_progress'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final item = DownloadItem(
      id: id,
      contentUrl: widget.args.contentUrl ?? '',
      provider: widget.args.provider,
      title: widget.args.title,
      thumbnail: widget.args.thumbnail,
      videoUrl: url,
      localPath: '',
      headers: _headers,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isSerial: widget.args.isSerial,
      episodeNumber: ep?.episode,
      episodeLabel: ep?.label,
    );

    final started = await _downloads.startDownload(item);
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('detail.download_needs_permission'.tr()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('detail.download_started'.tr()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

}
