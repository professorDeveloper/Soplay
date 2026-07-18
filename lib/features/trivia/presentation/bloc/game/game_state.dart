import 'package:equatable/equatable.dart';
import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';
import 'package:soplay/features/trivia/domain/entities/reveal_result_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_clip_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';

/// - [loading]  building / finalizing the round
/// - [playing]  a clip is on screen, countdown running, options tappable
/// - [revealed] an answer was submitted; [reveal] holds the truth payload
/// - [finished] round complete; [result] holds the final outcome
/// - [error]    the round failed to build or finalize
enum GamePhase { loading, playing, revealed, finished, error }

const Object _unset = Object();

class GameState extends Equatable {
  const GameState({
    this.phase = GamePhase.loading,
    this.roundId = '',
    this.mode = '',
    this.clips = const <TriviaClipEntity>[],
    this.index = 0,
    this.timeRemaining = 0,
    this.deadlineMs = 15000,
    this.score = 0,
    this.selectedOptionId,
    this.reveal,
    this.result,
    this.actor,
    this.challengeCode,
    this.message,
  });

  final GamePhase phase;
  final String roundId;
  final String mode;
  final List<TriviaClipEntity> clips;

  /// Index of the clip currently in play.
  final int index;

  /// Whole seconds left on the current clip's countdown.
  final int timeRemaining;

  /// Per-clip deadline in ms (drives the countdown ring + timeout submit).
  final int deadlineMs;

  /// Running score across the round so far.
  final int score;

  /// The locked option while a submit is in flight / after reveal (null on a
  /// timed-out clip).
  final String? selectedOptionId;

  /// The reveal payload for the current clip (set once answered).
  final RevealResultEntity? reveal;

  /// The final round outcome (set once finished).
  final TriviaResultEntity? result;

  /// The actor/character a fan-test round targets.
  final ActorRefEntity? actor;

  final String? challengeCode;
  final String? message;

  /// The clip currently in play, or null if the index is out of range.
  TriviaClipEntity? get currentClip =>
      (index >= 0 && index < clips.length) ? clips[index] : null;

  int get totalClips => clips.length;

  bool get isLastClip => clips.isNotEmpty && index >= clips.length - 1;

  GameState copyWith({
    GamePhase? phase,
    String? roundId,
    String? mode,
    List<TriviaClipEntity>? clips,
    int? index,
    int? timeRemaining,
    int? deadlineMs,
    int? score,
    Object? selectedOptionId = _unset,
    Object? reveal = _unset,
    Object? result = _unset,
    Object? actor = _unset,
    Object? challengeCode = _unset,
    Object? message = _unset,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      roundId: roundId ?? this.roundId,
      mode: mode ?? this.mode,
      clips: clips ?? this.clips,
      index: index ?? this.index,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      deadlineMs: deadlineMs ?? this.deadlineMs,
      score: score ?? this.score,
      selectedOptionId: selectedOptionId == _unset
          ? this.selectedOptionId
          : selectedOptionId as String?,
      reveal: reveal == _unset ? this.reveal : reveal as RevealResultEntity?,
      result: result == _unset ? this.result : result as TriviaResultEntity?,
      actor: actor == _unset ? this.actor : actor as ActorRefEntity?,
      challengeCode: challengeCode == _unset
          ? this.challengeCode
          : challengeCode as String?,
      message: message == _unset ? this.message : message as String?,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        roundId,
        mode,
        clips,
        index,
        timeRemaining,
        deadlineMs,
        score,
        selectedOptionId,
        reveal,
        result,
        actor,
        challengeCode,
        message,
      ];
}
