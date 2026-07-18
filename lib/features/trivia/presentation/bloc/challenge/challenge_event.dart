import 'package:equatable/equatable.dart';

sealed class ChallengeEvent extends Equatable {
  const ChallengeEvent();

  @override
  List<Object?> get props => [];
}

/// Open a challenge deep link → fetch its meta + participants (get_challenge).
class ChallengeOpened extends ChallengeEvent {
  const ChallengeOpened(this.code);

  final String code;

  @override
  List<Object?> get props => [code];
}

/// "Play the same 10 clips" → materialize a round from the frozen set
/// (join_challenge). The resulting round is exposed on the state for handoff to
/// the game.
class ChallengeJoined extends ChallengeEvent {
  const ChallengeJoined(this.code);

  final String code;

  @override
  List<Object?> get props => [code];
}
