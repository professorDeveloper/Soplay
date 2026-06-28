part of 'player_page.dart';

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

  Future<void> _pingStreak() async {
    try {
      final milestone = await getIt<StreakService>().ping();
      if (milestone == null || !mounted) return;
      await StreakMilestoneDialog.show(context, milestone);
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

    final rawId = widget.args.isSerial && ep != null
        ? '${widget.args.contentUrl ?? url}_ep${ep.episode}'
        : widget.args.contentUrl ?? url;
    final id = _stableDownloadId(rawId);

    final existing = _downloads.get(id);
    if (existing != null) {
      if (existing.status == DownloadStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Already downloaded'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (existing.status == DownloadStatus.downloading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download in progress'),
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
        const SnackBar(
          content: Text('Notification permission is required for downloads'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download started'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _stableDownloadId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(36);
  }
}
