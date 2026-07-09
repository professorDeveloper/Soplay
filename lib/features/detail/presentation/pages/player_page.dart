import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:floating/floating.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/diagnostics/log_viewer_sheet.dart';
import 'package:soplay/core/diagnostics/player_log.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/app_orientation.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:soplay/core/subtitles/online_subtitles_service.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_entity.dart';
import 'package:soplay/features/detail/domain/entities/subtitle_style.dart';
import 'package:soplay/features/detail/domain/entities/thumbnails_entity.dart';
import 'package:soplay/core/preview/frame_preview_service.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/presentation/dialogs/streak_milestone_dialog.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/party_resolve_gate.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_plugin_required_view.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/domain/entities/party_playback.dart';
import 'package:soplay/features/watch_party/domain/entities/party_state.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_chat_panel.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_reactions_bar.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_code_sheet.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soplay/core/player/media_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'player_page.models.dart';
part 'player_page.widgets.dart';
part 'player_page.media.dart';
part 'player_page.controls.dart';
part 'player_page.panels.dart';
part 'player_page.subtitles.dart';
part 'player_page.gestures.dart';
part 'player_page.history.dart';
part 'player_page.pip.dart';
part 'player_page.party.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.args});
  final PlayerArgs args;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ResolveMediaUseCase _resolve = getIt<ResolveMediaUseCase>();
  final HiveService _hive = getIt<HiveService>();
  final HistoryService _history = getIt<HistoryService>();
  final DownloadService _downloads = getIt<DownloadService>();
  final Floating _floating = Floating();
  bool _isPip = false;
  bool _resumeAfterPause = false;
  bool _lastPipPlaying = false;

  PlayerController? _controller;
  late int _episodeIndex;
  String? _currentQuality;
  String? _videoUrl;
  String? _mediaType;
  Map<String, String> _headers = const {};
  bool _isNetworkVideo = false;
  bool _isHls = false;
  bool _isLive = false;
  List<VideoSourceEntity> _videoSources = const [];
  int _currentSourceIndex = -1;
  bool _autoFallbackUsed = false;
  String? _errorMessage;
  bool _isCodecError = false;
  bool _initializing = true;
  _LoadingStage _stage = _LoadingStage.loading;
  bool _controlsVisible = true;
  bool _locked = false;
  _SidePanel _panel = _SidePanel.none;

  String? _currentLang;
  List<String> _serverLangs = const [];

  List<SubtitleEntity> _subtitles = const [];
  int _activeSubtitleIndex = -1;
  ClosedCaptionFile? _captionFile;
  final ValueNotifier<int> _subtitleOffsetMs = ValueNotifier<int>(0);
  SubtitleStyle _subtitleStyle = SubtitleStyle.defaults();

  String? _thumbnailsKey;
  List<_VttThumbnail> _vttThumbnails = const [];
  ThumbnailsEntity? _storyboard;
  final ValueNotifier<double?> _sliderDragValue = ValueNotifier<double?>(null);

  double _playbackSpeed = 1.0;
  _PlayerFit _fit = _PlayerFit.contain;
  bool _isPortrait = false;
  bool _isFullscreen = false;
  double _volumeBeforeMute = 1.0;

  double _brightness = 0.5;
  double _volume = 1.0;
  final ValueNotifier<_SwipeIndicator?> _swipeIndicator =
      ValueNotifier<_SwipeIndicator?>(null);

  Offset? _dragStart;
  bool? _dragIsHorizontal;
  _SwipeType? _dragSwipeType;

  final ValueNotifier<_ScrubState?> _scrub = ValueNotifier<_ScrubState?>(null);
  final ValueNotifier<bool> _speedBoost = ValueNotifier<bool>(false);
  double? _speedBeforeBoost;

  Timer? _hideTimer;
  Timer? _historyTimer;
  late final AnimationController _controlsAnimation;

  late final AnimationController _seekRippleController;
  Timer? _seekRippleTimer;
  int _seekRippleDirection = 0;
  int _seekRippleSeconds = 0;

  int _retryAttempts = 0;
  bool _autoRetrying = false;
  final Stopwatch _playbackWatch = Stopwatch();
  bool _streakPingScheduled = false;

  bool _wasPlaying = false;
  bool _wasBuffering = false;
  bool _wasInitialized = false;
  String? _lastError;

  // --- Watch2Gether (see player_page.party.dart). Fields must live here
  // because Dart extensions cannot declare instance fields.
  bool _applyingRemote = false;
  Timer? _partyHeartbeat;
  Timer? _partyDrift;
  PartyPlayback? _lastPartyPlayback;
  StreamSubscription<PartyPlayback>? _partySyncSub;
  StreamSubscription<PartyContent>? _partyContentSub;
  bool _partyControlSnapshot = false;
  // True while the sync binding (timers + stream subs) is live. Lets the player
  // activate the binding when a party is created/joined WHILE it is already open.
  bool _partyBindingActive = false;
  // Whether the in-player party chat/side panel is open.
  bool _chatOpen = false;
  // Set when a party:content identity cannot be resolved on THIS device because
  // the required on-device plugin/extension is missing. Renders the actionable
  // install view in place of the generic error overlay.
  PartyResolveCapability? _pluginRequired;

  @override
  void initState() {
    super.initState();
    _subtitleStyle = _hive.getSubtitleStyle();
    _episodeIndex = widget.args.initialEpisodeIndex.clamp(
      0,
      widget.args.episodes.isEmpty ? 0 : widget.args.episodes.length - 1,
    );
    _currentLang = widget.args.initialLang ?? _hive.getPreferredMediaLang();
    _controlsAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _seekRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    WidgetsBinding.instance.addObserver(this);
    _pipChannel.setMethodCallHandler(_onPipMethodCall);
    unawaited(_loadSystemControlValues());
    PlayerLog.instance
      ..clear()
      ..clearContext()
      ..setContext({
        'provider': widget.args.provider,
        'title': widget.args.title,
        'serial': widget.args.isSerial.toString(),
      });
    unawaited(PlayerLog.instance.init());
    _partyInit();
    _startup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!isDesktopPlatform &&
            c.value.isInitialized &&
            c.value.isPlaying &&
            !_isPip) {
          _resumeAfterPause = true;
          c.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_isPip && mounted) {
          setState(() => _isPip = false);
        }
        if (_resumeAfterPause && c.value.isInitialized) {
          c.play();
        }
        _resumeAfterPause = false;
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _plog(String message, {LogLevel level = LogLevel.info}) =>
      PlayerLog.instance.add(message, level: level);

  @override
  void dispose() {
    _saveHistory();
    _partyDispose();
    WidgetsBinding.instance.removeObserver(this);
    _pipChannel.setMethodCallHandler(null);
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _seekRippleTimer?.cancel();
    _controlsAnimation.dispose();
    _seekRippleController.dispose();
    _scrub.dispose();
    _speedBoost.dispose();
    _swipeIndicator.dispose();
    _sliderDragValue.dispose();
    _subtitleOffsetMs.dispose();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onMajorChange);
      try {
        c.pause();
      } catch (_) {}
      c.dispose();
    }
    _controller = null;
    FramePreviewService.close();
    _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) => _restoreSystemUi(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: _wrapDesktopShortcuts(
          Scaffold(
          backgroundColor: Colors.black,
          // The chat composer lifts itself over the keyboard; don't let the
          // Scaffold squish the full-bleed video when the keyboard opens.
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (context, constraints) => _wrapHover(GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _locked ? null : _toggleControls,
              onDoubleTapDown: _locked || isDesktopPlatform
                  ? null
                  : (d) => _onDoubleTapDown(d, constraints),
              onDoubleTap: _locked
                  ? null
                  : isDesktopPlatform
                      ? _toggleFullscreen
                      : () {},
              onPanStart: _locked ? null : (d) => _onPanStart(d, constraints),
              onPanUpdate: _locked ? null : (d) => _onPanUpdate(d, constraints),
              onPanEnd: _locked ? null : _onPanEnd,
              onPanCancel: _locked ? null : _onPanCancel,
              onLongPressStart: _locked ? null : _onLongPressStart,
              onLongPressEnd: _locked ? null : _onLongPressEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoLayer(),
                  _buildSubtitleOverlay(),
                  if (!_locked) _buildSeekRipple(),
                  if (_locked) _buildLockOverlay() else _buildControlsOverlay(),
                  if (!_locked) _buildScrubOverlay(),
                  if (!_locked) _buildSpeedBoostBadge(),
                  if (!_locked) _buildSwipeIndicator(),
                  if (!_locked && _panel != _SidePanel.none) _buildSidePanel(),
                  if (!_locked && _inParty) _buildPartyReactionsLayer(),
                  if (!_locked && _inParty && _chatOpen) _buildPartyChatOverlay(),
                ],
              ),
            )),
          ),
        )),
      ),
    );
  }

  Widget _wrapDesktopShortcuts(Widget child) {
    if (!isDesktopPlatform) return child;
    return Focus(autofocus: true, onKeyEvent: _onPlayerKey, child: child);
  }

  Widget _wrapHover(Widget child) {
    if (!isDesktopPlatform) return child;
    return MouseRegion(
      onHover: (_) => _revealControlsForHover(),
      cursor: _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
      child: child,
    );
  }

  void _revealControlsForHover() {
    if (_locked || _isPip) return;
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsAnimation.forward();
    }
    _scheduleHide();
  }

  KeyEventResult _onPlayerKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    // Block playback-control keys (play/pause + seek) when not allowed to
    // control the party; consume the event so no local action happens.
    final isPartyControlKey = k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight;
    if (isPartyControlKey && _partyBlockLocal()) {
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(const Duration(seconds: -10));
      _showSeekRipple(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _seekRelative(const Duration(seconds: 10));
      _showSeekRipple(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _setPlayerVolume(_volume + 0.1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _setPlayerVolume(_volume - 0.1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_panel != _SidePanel.none) {
        _closePanel();
      } else if (_isFullscreen) {
        _toggleFullscreen();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
