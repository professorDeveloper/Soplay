import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/remote/data/remote_control_service.dart';

/// The phone as a remote for the TV.
///
/// Two halves that earn their place: a keyboard, because entering text with a
/// d-pad is the worst thing about any TV app, and transport controls, because
/// the physical remote is always on the other sofa.
class TvRemotePage extends StatefulWidget {
  const TvRemotePage({super.key});

  @override
  State<TvRemotePage> createState() => _TvRemotePageState();
}

class _TvRemotePageState extends State<TvRemotePage> {
  final RemoteControlService _service = getIt<RemoteControlService>();
  final _search = TextEditingController();

  List<RemoteDevice> _devices = const [];
  RemoteDevice? _selected;
  RemoteTvState? _state;
  bool _online = false;
  bool _loading = true;
  String? _error;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await _service.devices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        // Prefer one that is actually reachable: the list is ordered by last
        // seen, and the most recent TV is often the one that is switched off.
        _selected = devices.firstWhere(
          (d) => d.online,
          orElse: () => devices.isNotEmpty
              ? devices.first
              : const RemoteDevice(id: '', name: '', online: false),
        );
        if (_selected?.id.isEmpty ?? true) _selected = null;
        _loading = false;
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'remote.load_failed'.tr();
      });
    }
  }

  /// Polls the TV's state.
  ///
  /// Two seconds while something is playing, so the position moves; the TV
  /// pushes nothing to the phone, and a socket per remote would cost more than
  /// this does.
  void _startPolling() {
    _poll?.cancel();
    if (_selected == null) return;
    _refreshState();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshState());
  }

  Future<void> _refreshState() async {
    final device = _selected;
    if (device == null || !mounted) return;
    try {
      final result = await _service.state(device.id);
      if (!mounted) return;
      setState(() {
        _online = result.online;
        _state = result.state;
      });
    } catch (_) {
      // A dropped poll is not worth a message; the next one is two seconds away.
    }
  }

  Future<void> _run(Future<void> Function(String id) action) async {
    final device = _selected;
    if (device == null) return;
    HapticFeedback.selectionClick();
    try {
      await action(device.id);
      unawaited(_refreshState());
    } on RemoteOfflineException {
      if (!mounted) return;
      setState(() => _online = false);
      _toast('remote.tv_offline'.tr());
    } catch (_) {
      if (!mounted) return;
      _toast('remote.command_failed'.tr());
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'remote.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _loadDevices,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null) {
      return _Message(icon: Icons.cloud_off_rounded, text: _error!);
    }
    if (_devices.isEmpty) {
      return _Message(
        icon: Icons.tv_off_rounded,
        text: 'remote.no_devices'.tr(),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _DevicePicker(
          devices: _devices,
          selected: _selected,
          onChanged: (d) {
            setState(() => _selected = d);
            _startPolling();
          },
        ),
        const SizedBox(height: 14),
        _NowPlaying(online: _online, state: _state),
        const SizedBox(height: 18),
        _KeyboardCard(
          controller: _search,
          onSubmit: (text) {
            if (text.trim().isEmpty) return;
            _run((id) => _service.type(id, text.trim()));
          },
        ),
        const SizedBox(height: 18),
        _DpadCard(
          onDirection: (d) => _run((id) => _service.dpad(id, d)),
          onBack: () => _run(_service.back),
          onHome: () => _run(_service.home),
        ),
        const SizedBox(height: 18),
        _TransportCard(
          playing: _state?.playing ?? false,
          onPlayPause: () => _run(_service.playPause),
          onSeekBack: () => _run((id) => _service.seekBy(id, -10000)),
          onSeekForward: () => _run((id) => _service.seekBy(id, 10000)),
          onPrevious: () => _run(_service.previous),
          onNext: () => _run(_service.next),
        ),
      ],
    );
  }
}

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  final List<RemoteDevice> devices;
  final RemoteDevice? selected;
  final ValueChanged<RemoteDevice> onChanged;

  @override
  Widget build(BuildContext context) {
    if (devices.length == 1) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: devices.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final device = devices[i];
          final active = device.id == selected?.id;
          return GestureDetector(
            onTap: () => onChanged(device),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary.withValues(alpha: 0.16) : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AppColors.primary : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    device.online ? Icons.tv_rounded : Icons.tv_off_rounded,
                    size: 15,
                    color: device.online ? AppColors.success : AppColors.textHint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    device.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.online, required this.state});

  final bool online;
  final RemoteTvState? state;

  String _clock(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playing = state;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? AppColors.success : AppColors.textHint,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  !online
                      ? 'remote.tv_offline'.tr()
                      : playing?.title ?? 'remote.idle'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (online && (playing?.hasPlayback ?? false)) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${_clock(playing!.positionMs ?? 0)} / ${_clock(playing.durationMs!)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyboardCard extends StatelessWidget {
  const _KeyboardCard({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'remote.search_on_tv'.tr(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: onSubmit,
                  decoration: InputDecoration(
                    hintText: 'remote.search_hint'.tr(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => onSubmit(controller.text),
                icon: const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DpadCard extends StatelessWidget {
  const _DpadCard({
    required this.onDirection,
    required this.onBack,
    required this.onHome,
  });

  final ValueChanged<String> onDirection;
  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _Key(icon: Icons.keyboard_arrow_up_rounded, onTap: () => onDirection('up')),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(icon: Icons.keyboard_arrow_left_rounded, onTap: () => onDirection('left')),
              const SizedBox(width: 10),
              _Key(
                icon: Icons.circle_outlined,
                primary: true,
                onTap: () => onDirection('center'),
              ),
              const SizedBox(width: 10),
              _Key(icon: Icons.keyboard_arrow_right_rounded, onTap: () => onDirection('right')),
            ],
          ),
          _Key(icon: Icons.keyboard_arrow_down_rounded, onTap: () => onDirection('down')),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 17),
                label: Text('remote.back'.tr()),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: onHome,
                icon: const Icon(Icons.home_rounded, size: 17),
                label: Text('remote.home'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.playing,
    required this.onPlayPause,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onPrevious,
    required this.onNext,
  });

  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Key(icon: Icons.skip_previous_rounded, onTap: onPrevious),
          _Key(icon: Icons.replay_10_rounded, onTap: onSeekBack),
          _Key(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            primary: true,
            onTap: onPlayPause,
          ),
          _Key(icon: Icons.forward_10_rounded, onTap: onSeekForward),
          _Key(icon: Icons.skip_next_rounded, onTap: onNext),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.icon, required this.onTap, this.primary = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: primary ? AppColors.primary : AppColors.surfaceVariant,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: primary ? 60 : 50,
            height: primary ? 60 : 50,
            child: Icon(icon, color: Colors.white, size: primary ? 28 : 24),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.textHint.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
