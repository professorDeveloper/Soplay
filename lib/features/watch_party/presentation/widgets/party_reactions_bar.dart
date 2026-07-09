import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/entities/party_reaction.dart';

const List<String> kPartyReactions = ['❤️', '😂', '😮', '👏', '🔥'];

/// A compact emoji picker that sends reactions and floats incoming ones upward.
class PartyReactionsBar extends StatefulWidget {
  const PartyReactionsBar({super.key, required this.service});

  final WatchPartyService service;

  @override
  State<PartyReactionsBar> createState() => _PartyReactionsBarState();
}

class _PartyReactionsBarState extends State<PartyReactionsBar> {
  final math.Random _rng = math.Random();
  final List<_Floater> _floaters = [];
  StreamSubscription<PartyReaction>? _sub;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.reactions.listen(_spawn);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _spawn(PartyReaction r) {
    if (!mounted) return;
    final id = _seq++;
    setState(() {
      _floaters.add(_Floater(id: id, emoji: r.emoji, dx: _rng.nextDouble()));
    });
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _floaters.removeWhere((f) => f.id == id));
  }

  void _send(String emoji) {
    // The server echoes party:reaction back to the sender (namespace-scoped
    // broadcast), so the single incoming echo drives one floater. Spawning
    // optimistically here would render self-reactions twice.
    widget.service.sendReaction(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  for (final f in _floaters)
                    _FloatingEmoji(
                      key: ValueKey(f.id),
                      emoji: f.emoji,
                      left: 8 + f.dx * (constraints.maxWidth - 48),
                      onDone: () => _remove(f.id),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.border, width: 0.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in kPartyReactions)
                    _EmojiButton(emoji: e, onTap: () => _send(e)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Floater {
  const _Floater({required this.id, required this.emoji, required this.dx});

  final int id;
  final String emoji;
  final double dx;
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({
    super.key,
    required this.emoji,
    required this.left,
    required this.onDone,
  });

  final String emoji;
  final double left;
  final VoidCallback onDone;

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
    _c.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    _c.removeStatusListener(_onStatus);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final wobble = math.sin(t * math.pi * 2) * 8;
        return Positioned(
          left: widget.left + wobble,
          bottom: 40 + t * 68,
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.7 + t * 0.5, child: child),
          ),
        );
      },
      child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
    );
  }
}
