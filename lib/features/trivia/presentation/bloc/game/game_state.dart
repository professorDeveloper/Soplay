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

/// Why a round failed, so the UI can pick localized copy instead of echoing the
/// server's own sentence.
/// - [generic]        anything else; [GameState.message] may carry detail
/// - [notEnoughClips] the actor has too few approved clips (server 409, or a
///   round that came back with an empty clip list)
enum GameErrorReason { generic, notEnoughClips }

const Object _unset = Object();

/// Per-clip answer window used only until a round payload supplies its own
/// `answerWindowMs`. The real window is server-owned (the score bonus divisor
/// lives there), so it must never be hardcoded to a new value client-side.
///
/// Mirrors the server's ANSWER_WINDOW_MS default. It was 15000 while the server
/// shipped 10000, so any round that omitted the field gave the player a 15s
/// countdown the server scored as a 10s one — the last 5s silently scoring zero.
/// A fallback that disagrees with the server is worse than no fallback.
const int kFallbackAnswerWindowMs = 10000;

class GameState extends Equatable {
  const GameState({
    this.phase = GamePhase.loading,
    this.roundId = '',
    this.mode = '',
    this.clips = const <TriviaClipEntity>[],
    this.index = 0,
    this.timeRemaining = 0,
    this.deadlineMs = kFallbackAnswerWindowMs,
    this.score = 0,
    this.selectedOptionId,
    this.reveal,
    this.result,
    this.actor,
    this.challengeCode,
    this.message,
    this.reason = GameErrorReason.generic,
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

  /// Only meaningful while [phase] is [GamePhase.error].
  final GameErrorReason reason;

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
    GameErrorReason? reason,
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
      reason: reason ?? this.reason,
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
        reason,
      ];
}
