// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerGestures on _PlayerPageState {
  void _onDoubleTapDown(TapDownDetails details, BoxConstraints constraints) {
    final dx = details.localPosition.dx;
    final width = constraints.maxWidth;
    final leftEdge = width * 0.3;
    final rightEdge = width * 0.7;
    if (dx < leftEdge) {
      _seekRelative(const Duration(seconds: -10));
      _showSeekRipple(-1);
    } else if (dx > rightEdge) {
      _seekRelative(const Duration(seconds: 10));
      _showSeekRipple(1);
    }
  }

  void _onHDragStart(DragStartDetails _) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      _controlsVisible = true;
      _controlsAnimation.forward();
    }
    _scrub.value = _ScrubState(
      baseline: c.value.position,
      duration: c.value.duration,
      deltaPx: 0,
      span: 1,
    );
  }

  void _onHDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final state = _scrub.value;
    if (state == null) return;
    _scrub.value = state.copyWith(
      deltaPx: state.deltaPx + details.delta.dx,
      span: constraints.maxWidth,
    );
  }

  void _onHDragEnd(DragEndDetails _) {
    final state = _scrub.value;
    final c = _controller;
    _scrub.value = null;
    if (state == null || c == null || !c.value.isInitialized) {
      _scheduleHide();
      return;
    }
    final target = state.previewPosition(_scrubSecondsPerFullSwipe);
    // Route through _seekTo so the swipe-scrub honours the party control gate
    // and broadcasts the seek, like every other seek surface.
    _seekTo(target);
    _scheduleHide();
  }

  void _onHDragCancel() {
    _scrub.value = null;
    _scheduleHide();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    if (_controlsVisible) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    // A guest without control must not boost; and when we do boost, share the
    // rate so peers speed up together instead of the host's heartbeat leaking a
    // 2x-advanced position that jerks guests forward.
    if (_partyBlockLocal()) return;
    _speedBeforeBoost = _playbackSpeed;
    _speedBoost.value = true;
    c.setPlaybackSpeed(2.0);
    _partyEmit('rate', rate: 2.0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_speedBoost.value) return;
    _speedBoost.value = false;
    final c = _controller;
    final restore = _speedBeforeBoost ?? 1.0;
    _speedBeforeBoost = null;
    if (c != null && c.value.isInitialized) {
      c.setPlaybackSpeed(restore);
    }
    _partyEmit('rate', rate: restore);
  }

  void _showSeekRipple(int direction) {
    if (_seekRippleDirection != direction) {
      _seekRippleSeconds = 10;
    } else {
      _seekRippleSeconds += 10;
    }
    setState(() => _seekRippleDirection = direction);
    _seekRippleController.forward(from: 0);
    _seekRippleTimer?.cancel();
    _seekRippleTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _seekRippleDirection = 0;
        _seekRippleSeconds = 0;
      });
    });
  }

  void _onPanStart(DragStartDetails d, BoxConstraints constraints) {
    _dragStart = d.localPosition;
    _dragIsHorizontal = null;
    _dragSwipeType = null;
  }

  void _onPanUpdate(DragUpdateDetails d, BoxConstraints constraints) {
    final start = _dragStart;
    if (start == null) return;

    if (_dragIsHorizontal == null) {
      final dx = (d.localPosition.dx - start.dx).abs();
      final dy = (d.localPosition.dy - start.dy).abs();
      if (dx < 8 && dy < 8) return;
      _dragIsHorizontal = dx > dy;

      if (_dragIsHorizontal!) {
        _onHDragStart(
          DragStartDetails(
            globalPosition: d.globalPosition,
            localPosition: d.localPosition,
          ),
        );
      } else {
        final isLeft = start.dx < constraints.maxWidth * 0.5;
        _dragSwipeType = isLeft ? _SwipeType.brightness : _SwipeType.volume;
      }
    }

    if (_dragIsHorizontal!) {
      _onHDragUpdate(d, constraints);
    } else if (!isDesktopPlatform) {
      final delta = -(d.delta.dy) / (constraints.maxHeight * 0.7);
      if (_dragSwipeType == _SwipeType.brightness) {
        _brightness = (_brightness + delta).clamp(0.0, 1.0).toDouble();
        unawaited(_setSystemBrightness(_brightness));
        _swipeIndicator.value = _SwipeIndicator(
          _SwipeType.brightness,
          _brightness,
        );
      } else {
        _volume = (_volume + delta).clamp(0.0, 1.0).toDouble();
        unawaited(_setSystemVolume(_volume));
        _swipeIndicator.value = _SwipeIndicator(_SwipeType.volume, _volume);
      }
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_dragIsHorizontal == true) {
      _onHDragEnd(d);
    } else if (_dragSwipeType != null) {
      final type = _dragSwipeType;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (_swipeIndicator.value?.type == type) {
          _swipeIndicator.value = null;
        }
      });
    }
    _dragStart = null;
    _dragIsHorizontal = null;
    _dragSwipeType = null;
  }

  void _onPanCancel() {
    if (_dragIsHorizontal == true) _onHDragCancel();
    _swipeIndicator.value = null;
    _dragStart = null;
    _dragIsHorizontal = null;
    _dragSwipeType = null;
  }
}
