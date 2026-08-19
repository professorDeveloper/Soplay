import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:soplay/features/remote/data/remote_control_service.dart';

enum RemoteStatus { loading, noDevices, failed, ready }

/// Owns the connection to one TV: which one, whether it is reachable, and what
/// it is doing.
///
/// Pulled out of the page because the polling rules are the part that is easy
/// to get wrong, and a widget rebuilding is a bad place to keep a timer.
class RemoteController extends ChangeNotifier {
  RemoteController({required RemoteControlService service}) : _service = service;

  final RemoteControlService _service;

  // Adaptive on purpose. A remote showing a moving position needs seconds; a
  // TV that is switched off needs almost nothing, and asking it every two
  // seconds is how a remote left open flattens a battery.
  static const _whilePlaying = Duration(seconds: 2);
  static const _whileIdle = Duration(seconds: 5);
  static const _whileOffline = Duration(seconds: 15);

  RemoteStatus _status = RemoteStatus.loading;
  List<RemoteDevice> _devices = const [];
  RemoteDevice? _selected;
  RemoteTvState? _tvState;
  bool _online = false;

  /// True only between a command leaving and its answer, so a button can show
  /// it was pressed without the whole screen flickering.
  bool _busy = false;

  Timer? _timer;

  /// Guards against overlapping polls. A periodic timer firing into an async
  /// body does not wait for the previous one, so a slow network stacks requests
  /// until the page appears frozen — the exact failure this exists to prevent.
  bool _polling = false;

  bool _disposed = false;
  bool _paused = false;

  RemoteStatus get status => _status;
  List<RemoteDevice> get devices => _devices;
  RemoteDevice? get selected => _selected;
  RemoteTvState? get tvState => _tvState;
  bool get online => _online;
  bool get busy => _busy;

  /// Whether commands can do anything right now. The UI disables on this rather
  /// than letting every tap turn into a failed request.
  bool get canControl => _selected != null && _online;

  Future<void> load() async {
    _status = RemoteStatus.loading;
    _notify();
    try {
      final devices = await _service.devices();
      if (_disposed) return;
      _devices = devices;

      if (devices.isEmpty) {
        _selected = null;
        _status = RemoteStatus.noDevices;
        _stopTimer();
        _notify();
        return;
      }

      // Keep the current pick across a refresh; otherwise prefer one that is
      // actually reachable, since the most recently used TV is often the one
      // that is now switched off.
      final keep = _selected;
      _selected = keep != null && devices.any((d) => d.id == keep.id)
          ? devices.firstWhere((d) => d.id == keep.id)
          : devices.firstWhere((d) => d.online, orElse: () => devices.first);

      _status = RemoteStatus.ready;
      _notify();
      await _refresh();
      _schedule();
    } catch (_) {
      if (_disposed) return;
      _status = RemoteStatus.failed;
      _stopTimer();
      _notify();
    }
  }

  void select(RemoteDevice device) {
    if (device.id == _selected?.id) return;
    _selected = device;
    // Clear rather than carry: showing the previous TV's title under a new one
    // is worse than showing nothing for a second.
    _tvState = null;
    _online = device.online;
    _notify();
    unawaited(_refresh());
    _schedule();
  }

  /// Stops polling while the app is not in front of the user.
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (paused) {
      _stopTimer();
    } else {
      unawaited(_refresh());
      _schedule();
    }
  }

  /// Runs a command and reports what happened.
  ///
  /// Returns null on success, or a reason to show. The controller never throws
  /// at the UI: a remote whose buttons can crash the page is worse than one
  /// that says a button did not land.
  Future<String?> send(Future<void> Function(String id) action) async {
    final device = _selected;
    if (device == null) return 'no-device';
    _busy = true;
    _notify();
    try {
      await action(device.id);
      await _refresh();
      return null;
    } on RemoteOfflineException {
      _online = false;
      _schedule();
      return 'offline';
    } catch (_) {
      return 'failed';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _refresh() async {
    final device = _selected;
    if (device == null || _polling || _disposed) return;
    _polling = true;
    try {
      final result = await _service.state(device.id);
      if (_disposed) return;
      final wasOnline = _online;
      _online = result.online;
      _tvState = result.state;
      _notify();
      // Coming back online should tighten the cadence immediately rather than
      // after one more slow tick.
      if (wasOnline != _online) _schedule();
    } catch (_) {
      // A dropped poll is not worth surfacing; the next one is seconds away.
    } finally {
      _polling = false;
    }
  }

  void _schedule() {
    _stopTimer();
    if (_disposed || _paused || _selected == null) return;
    final interval = !_online
        ? _whileOffline
        : (_tvState?.playing ?? false)
        ? _whilePlaying
        : _whileIdle;
    _timer = Timer.periodic(interval, (_) => unawaited(_refresh()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}
