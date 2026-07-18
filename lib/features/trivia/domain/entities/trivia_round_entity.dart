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
  });

  final String roundId;
  final String mode; // 'klip_top' | 'fan_test'
  final List<TriviaClipEntity> clips;
  final int index; // index of the next unanswered clip (resume position)
  final ActorRefEntity? actor;
  final String? challengeCode;

  @override
  List<Object?> get props => [roundId, mode, clips, index, actor, challengeCode];
}
