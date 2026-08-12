import 'package:equatable/equatable.dart';
import 'package:riasdxd/features/trivia/domain/entities/challenge_entity.dart';
import 'package:riasdxd/features/trivia/domain/entities/trivia_round_entity.dart';

/// - [initial] nothing loaded
/// - [loading] fetching the challenge meta
/// - [loaded]  challenge meta + participants ready
/// - [joining] materializing a round from the frozen clips
/// - [joined]  [round] is ready to hand off to the game
/// - [error]   load or join failed
enum ChallengeStatus { initial, loading, loaded, joining, joined, error }

const Object _unset = Object();

class ChallengeState extends Equatable {
  const ChallengeState({
    this.status = ChallengeStatus.initial,
    this.challenge,
    this.round,
    this.message,
  });

  final ChallengeStatus status;
  final ChallengeEntity? challenge;

  /// The round materialized from the frozen 10 clips after a successful join.
  final TriviaRoundEntity? round;

  final String? message;

  ChallengeState copyWith({
    ChallengeStatus? status,
    Object? challenge = _unset,
    Object? round = _unset,
    Object? message = _unset,
  }) {
    return ChallengeState(
      status: status ?? this.status,
      challenge:
          challenge == _unset ? this.challenge : challenge as ChallengeEntity?,
      round: round == _unset ? this.round : round as TriviaRoundEntity?,
      message: message == _unset ? this.message : message as String?,
    );
  }

  @override
  List<Object?> get props => [status, challenge, round, message];
}
