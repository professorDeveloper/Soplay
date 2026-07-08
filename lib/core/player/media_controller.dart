import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:soplay/core/system/platform_utils.dart';
import 'package:video_player/video_player.dart' as vp;

export 'package:video_player/video_player.dart'
    show
        VideoPlayerValue,
        VideoFormat,
        VideoPlayerOptions,
        ClosedCaptionFile,
        Caption,
        WebVTTCaptionFile,
        SubRipCaptionFile;

abstract class PlayerController extends ValueNotifier<vp.VideoPlayerValue> {
  PlayerController() : super(vp.VideoPlayerValue.uninitialized());

  factory PlayerController.networkUrl(
    Uri url, {
    Map<String, String> httpHeaders = const <String, String>{},
    vp.VideoFormat? formatHint,
    vp.VideoPlayerOptions? videoPlayerOptions,
  }) {
    if (isDesktopPlatform) {
      return _MediaKitController(_MediaKitSource.uri(url, httpHeaders));
    }
    return _NativeController(
      vp.VideoPlayerController.networkUrl(
        url,
        httpHeaders: httpHeaders,
        formatHint: formatHint,
        videoPlayerOptions: videoPlayerOptions,
      ),
    );
  }

  factory PlayerController.file(
    File file, {
    vp.VideoPlayerOptions? videoPlayerOptions,
  }) {
    if (isDesktopPlatform) {
      return _MediaKitController(_MediaKitSource.path(file.path));
    }
    return _NativeController(
      vp.VideoPlayerController.file(
        file,
        videoPlayerOptions: videoPlayerOptions,
      ),
    );
  }

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> setLooping(bool looping);

  bool get letterboxesInternally;

  Widget buildView({BoxFit fit = BoxFit.contain});

  @override
  Future<void> dispose();
}


class _NativeController extends PlayerController {
  _NativeController(this._inner) {
    _inner.addListener(_sync);
  }

  final vp.VideoPlayerController _inner;
  bool _disposed = false;

  void _sync() {
    if (!_disposed) value = _inner.value;
  }

  @override
  Future<void> initialize() async {
    await _inner.initialize();
    value = _inner.value;
  }

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> seekTo(Duration position) => _inner.seekTo(position);

  @override
  Future<void> setPlaybackSpeed(double speed) => _inner.setPlaybackSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> setLooping(bool looping) => _inner.setLooping(looping);

  @override
  bool get letterboxesInternally => false;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) => vp.VideoPlayer(_inner);

  @override
  Future<void> dispose() async {
    _disposed = true;
    _inner.removeListener(_sync);
    await _inner.dispose();
    super.dispose();
  }
}


class _MediaKitSource {
  _MediaKitSource.uri(Uri uri, this.headers)
      : source = uri.isScheme('file') ? uri.toFilePath() : uri.toString();
  _MediaKitSource.path(this.source) : headers = const <String, String>{};

  final String source;
  final Map<String, String> headers;
}

class _MediaKitController extends PlayerController {
  _MediaKitController(this._src) {
    _videoController = mkv.VideoController(_player);
  }

  final _MediaKitSource _src;
  final mk.Player _player = mk.Player();
  late final mkv.VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  bool _disposed = false;
  String? _error;

  @override
  Future<void> initialize() async {
    _wire();
    await _player.open(
      mk.Media(
        _src.source,
        httpHeaders: _src.headers.isEmpty ? null : _src.headers,
      ),
      play: false,
    );
    await _awaitReady();
    if (_disposed) return;
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    value = value.copyWith(
      isInitialized: _error == null,
      duration: _player.state.duration,
      size: (w > 0 && h > 0)
          ? Size(w.toDouble(), h.toDouble())
          : value.size,
      errorDescription: _error,
    );
  }

  void _wire() {
    _subs
      ..add(_player.stream.position
          .listen((p) => _emit(value.copyWith(position: p))))
      ..add(_player.stream.duration
          .listen((d) => _emit(value.copyWith(duration: d))))
      ..add(_player.stream.playing
          .listen((p) => _emit(value.copyWith(isPlaying: p))))
      ..add(_player.stream.buffering
          .listen((b) => _emit(value.copyWith(isBuffering: b))))
      ..add(_player.stream.completed
          .listen((c) => _emit(value.copyWith(isCompleted: c))))
      ..add(_player.stream.width.listen((_) => _emitSize()))
      ..add(_player.stream.height.listen((_) => _emitSize()))
      ..add(_player.stream.error.listen((e) {
        _error = e;
        _emit(value.copyWith(errorDescription: e));
      }));
  }

  void _emitSize() {
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    if (w > 0 && h > 0) {
      _emit(value.copyWith(size: Size(w.toDouble(), h.toDouble())));
    }
  }

  void _emit(vp.VideoPlayerValue v) {
    if (_disposed) return;
    value = v;
  }

  Future<void> _awaitReady() async {
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    final subs = <StreamSubscription<dynamic>>[
      _player.stream.duration.listen((d) {
        if (d > Duration.zero) finish();
      }),
      _player.stream.width.listen((w) {
        if ((w ?? 0) > 0) finish();
      }),
      _player.stream.playing.listen((p) {
        if (p) finish();
      }),
      _player.stream.error.listen((e) {
        _error = e;
        finish();
      }),
    ];

    if (_player.state.duration > Duration.zero ||
        (_player.state.width ?? 0) > 0) {
      finish();
    }
    final timer = Timer(const Duration(seconds: 30), finish);

    await completer.future;
    timer.cancel();
    for (final s in subs) {
      await s.cancel();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setPlaybackSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume * 100).clamp(0.0, 100.0));

  @override
  Future<void> setLooping(bool looping) => _player.setPlaylistMode(
        looping ? mk.PlaylistMode.single : mk.PlaylistMode.none,
      );

  @override
  bool get letterboxesInternally => true;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) => mkv.Video(
        controller: _videoController,
        fit: fit,
        fill: const Color(0xFF000000),
        controls: mkv.NoVideoControls,
      );

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player.dispose();
    super.dispose();
  }
}
