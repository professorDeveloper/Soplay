import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';

/// Navigation payload for the trivia game route (`/trivia/game`).
///
/// - Klip Top: only [mode] is set.
/// - Fan Test: [mode] + [actorRef] (the actor/character the round targets).
/// - Challenge: [challengeCode] and/or a pre-materialized [presetRound] built
///   from the frozen 10 clips.
class GameArgs {
  const GameArgs({
    required this.mode,
    this.actorRef,
    this.challengeCode,
    this.presetRound,
  });

  final String mode; // 'klip_top' | 'fan_test'
  final ActorRefEntity? actorRef;
  final String? challengeCode;
  final TriviaRoundEntity? presetRound;
}

/// Push the full-screen game with [args].
Future<T?> openGame<T extends Object?>(BuildContext context, GameArgs args) =>
    context.push<T>('/trivia/game', extra: args);

/// Open the round-result screen with the final [result].
Future<T?> openResult<T extends Object?>(
  BuildContext context,
  TriviaResultEntity result,
) =>
    context.push<T>('/trivia/result', extra: result);
