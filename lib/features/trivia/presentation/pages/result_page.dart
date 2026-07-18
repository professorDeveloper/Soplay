import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:soplay/features/trivia/presentation/trivia_args.dart';
import 'package:soplay/features/trivia/presentation/widgets/share_card.dart';

/// Round-result screen. Klip Top leads with the score; Fan Test leads with the
/// circular fandom-% gauge. Both offer play-again, leaderboard, and two share
/// paths — a text challenge and a rasterized [ShareCard] (RepaintBoundary →
/// toImage → share_plus).
///
/// The route (`/trivia/result`) only carries a [TriviaResultEntity]; [mode] and
/// [actor] are optional so a richer caller (e.g. the game finishing a fan-test
/// round) can enrich the layout and share card, but the page degrades
/// gracefully to a brand-only card when they are absent.
class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.result,
    this.mode,
    this.actor,
  });

  final TriviaResultEntity result;
  final String? mode;
  final ActorRefEntity? actor;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  bool get _isFanTest => widget.mode != 'klip_top';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final actor = widget.actor;
    if (actor != null && actor.profileUrl.isNotEmpty) {
      precacheImage(NetworkImage(actor.profileUrl), context);
    }
  }

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/kino_billar_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'trivia.share_text'.tr(),
      );
    } catch (_) {
      // Sharing is best-effort; swallow capture/IO failures.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _playAgain() {
    context.pushReplacement(
      '/trivia/game',
      extra: GameArgs(mode: widget.mode ?? 'klip_top', actorRef: widget.actor),
    );
  }

  void _challengeFriend() {
    Share.share('trivia.challenge_text'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(CupertinoIcons.xmark,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (_isFanTest ? 'trivia.fan_test_done' : 'trivia.round_done')
                        .tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_isFanTest)
                    _FandomGauge(percent: r.fandomPercent)
                  else
                    _ScoreHero(score: r.score),
                  const SizedBox(height: 28),
                  _StatRow(result: r, isFanTest: _isFanTest),
                  const SizedBox(height: 32),
                  _actions(),
                ],
              ),
            ),
          ),
          // Off-screen but painted, so the RepaintBoundary can be rasterized.
          Positioned(
            left: 0,
            top: 0,
            child: Transform.translate(
              offset: const Offset(-4000, 0),
              child: RepaintBoundary(
                key: _cardKey,
                child: ShareCard(
                  mode: widget.mode ?? 'fan_test',
                  result: r,
                  actor: widget.actor,
                  actorImage: widget.actor != null &&
                          widget.actor!.profileUrl.isNotEmpty
                      ? NetworkImage(widget.actor!.profileUrl)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _playAgain,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(CupertinoIcons.refresh, size: 18),
            label: Text(
              'trivia.play_again'.tr(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                icon: CupertinoIcons.chart_bar_alt_fill,
                label: 'trivia.leaderboard'.tr(),
                onTap: () => context.push('/trivia/leaderboard'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SecondaryButton(
                icon: CupertinoIcons.person_2_fill,
                label: 'trivia.challenge_friend'.tr(),
                onTap: _challengeFriend,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SecondaryButton(
          icon: CupertinoIcons.share,
          label: 'trivia.share_result'.tr(),
          onTap: _shareCard,
          busy: _sharing,
        ),
      ],
    );
  }
}

class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'trivia.score'.tr().toUpperCase(),
          style: TextStyle(
            color: AppColors.primaryLight,
            fontSize: 13,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, t, _) => Text(
            '${(score * t).round()}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 68,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _FandomGauge extends StatelessWidget {
  const _FandomGauge({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final target = (percent / 100).clamp(0.0, 1.0);
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: target),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (_, value, _) {
            return CustomPaint(
              painter: _GaugePainter(value),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(value * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'trivia.fandom'.tr().toUpperCase(),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [AppColors.primary, AppColors.primaryLight, AppColors.primary],
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.result, required this.isFanTest});

  final TriviaResultEntity result;
  final bool isFanTest;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _StatTile(
        value: '${result.correctCount}/10',
        label: 'trivia.correct'.tr(),
        icon: CupertinoIcons.checkmark_seal_fill,
      ),
      _StatTile(
        value: '#${result.rank}',
        label: 'trivia.rank'.tr(),
        icon: CupertinoIcons.rosette,
      ),
      _StatTile(
        value: isFanTest ? '${result.score}' : '${result.fandomPercent.round()}%',
        label: isFanTest ? 'trivia.score'.tr() : 'trivia.fandom'.tr(),
        icon: isFanTest
            ? CupertinoIcons.bolt_fill
            : CupertinoIcons.heart_fill,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i != 0) const SizedBox(width: 12),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
