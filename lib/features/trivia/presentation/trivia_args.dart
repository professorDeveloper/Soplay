import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';

/// Navigation payload for the trivia game route (`/trivia/game`).
///
/// Buff is a single-purpose fan checker, so every round is `fan_test` — the
/// mode is no longer a caller-supplied choice.
/// - Fan Test: [actorRef] (the actor the round targets).
/// - Challenge: [challengeCode] and/or a pre-materialized [presetRound] built
///   from the frozen 10 clips.
class GameArgs {
  const GameArgs({
    this.actorRef,
    this.challengeCode,
    this.presetRound,
  });

  final ActorRefEntity? actorRef;
  final String? challengeCode;
  final TriviaRoundEntity? presetRound;

  /// The only mode the app plays / sends.
  String get mode => kFanTestMode;
}

/// The single game mode Buff plays. The backend still accepts 'klip_top';
/// the app never sends it.
const String kFanTestMode = 'fan_test';

/// Navigation payload for the round-result route (`/trivia/result`).
///
/// The result alone is not enough: without [actor] the share card falls back to
/// brand-only and "Play again" starts a round with no actor at all. The route
/// still accepts a bare [TriviaResultEntity] for legacy pushes.
class ResultArgs {
  const ResultArgs({required this.result, this.actor});

  final TriviaResultEntity result;
  final ActorRefEntity? actor;
}

/// Navigation payload for the Top Fans board (`/trivia/top-fans`) — the id on
/// its own would drop [kind] and silently fall back to live actors.
class TopFansArgs {
  const TopFansArgs({required this.actorId, this.kind = 'person'});

  final int actorId;
  final String kind;
}

/// Push the full-screen game with [args].
Future<T?> openGame<T extends Object?>(BuildContext context, GameArgs args) =>
    context.push<T>('/trivia/game', extra: args);

/// Open the round-result screen with the final result (and, ideally, the actor
/// it was played against).
Future<T?> openResult<T extends Object?>(
  BuildContext context,
  ResultArgs args,
) =>
    context.push<T>('/trivia/result', extra: args);

/// Open the full Top Fans board for one actor.
Future<T?> openTopFans<T extends Object?>(
  BuildContext context,
  TopFansArgs args,
) =>
    context.push<T>('/trivia/top-fans', extra: args);
