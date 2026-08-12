import 'package:equatable/equatable.dart';
import 'package:riasdxd/features/trivia/domain/entities/trivia_round_entity.dart';

sealed class GameEvent extends Equatable {
  const GameEvent();

  @override
  List<Object?> get props => [];
}

/// Start a round. Either build a fresh one (create_round with [mode] and, for
/// fan-test, [actorId]/[kind]) or play a pre-materialized [round] — e.g. the
/// frozen round returned by joining a challenge.
class RoundStarted extends GameEvent {
  const RoundStarted({
    required this.mode,
    this.actorId,
    this.kind,
    this.round,
  });

  final String mode; // 'klip_top' | 'fan_test'
  final int? actorId;
  final String? kind; // 'person' | 'character'
  final TriviaRoundEntity? round;

  @override
  List<Object?> get props => [mode, actorId, kind, round];
}

/// The clip at [clipIndex] is now on screen → stamp start-clip server-side and
/// (re)start the countdown.
class ClipShown extends GameEvent {
  const ClipShown(this.clipIndex);

  final int clipIndex;

  @override
  List<Object?> get props => [clipIndex];
}

/// The player picked an option — or the countdown expired, in which case
/// [optionId] is null (an auto-submitted "no answer").
class OptionSelected extends GameEvent {
  const OptionSelected(this.optionId);

  final String? optionId;

  @override
  List<Object?> get props => [optionId];
}

/// One-second tick from the internal per-clip countdown timer.
class GameTimerTicked extends GameEvent {
  const GameTimerTicked();
}

/// Advance to the next clip after a reveal (restarts the countdown via
/// [ClipShown]).
class NextClip extends GameEvent {
  const NextClip();
}

/// All clips answered → finalize the round (complete_round).
class RoundCompleted extends GameEvent {
  const RoundCompleted();
}
