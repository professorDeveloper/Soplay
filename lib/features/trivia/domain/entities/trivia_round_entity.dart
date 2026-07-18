import 'package:equatable/equatable.dart';
import 'actor_ref_entity.dart';
import 'trivia_clip_entity.dart';

/// A materialized round: 10 clips (title-hidden), the current [index] for
/// resume, the game [mode], and — for fan-test rounds — the [actor] it targets.
class TriviaRoundEntity extends Equatable {
  const TriviaRoundEntity({
    required this.roundId,
    required this.mode,
    required this.clips,
    required this.index,
    this.actor,
    this.challengeCode,
    this.answerWindowMs,
  });

  final String roundId;
  final String mode; // 'klip_top' | 'fan_test'
  final List<TriviaClipEntity> clips;
  final int index; // index of the next unanswered clip (resume position)
  final ActorRefEntity? actor;
  final String? challengeCode;

  /// Per-clip answer window the server wants enforced, in ms. Null when the
  /// server does not send it — the client then falls back to its own default.
  /// Never hardcode the new value client-side: the score bonus divisor lives
  /// on the server, so a client/server mismatch inflates every score.
  final int? answerWindowMs;

  @override
  List<Object?> get props =>
      [roundId, mode, clips, index, actor, challengeCode, answerWindowMs];
}
