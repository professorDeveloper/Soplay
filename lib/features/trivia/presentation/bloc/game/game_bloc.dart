import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/reveal_result_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';
import 'package:soplay/features/trivia/domain/usecases/complete_round_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/create_round_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/start_clip_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/submit_answer_usecase.dart';

import 'game_event.dart';
import 'game_state.dart';

/// Owns one trivia round and the per-clip countdown (length comes from the
/// round's `answerWindowMs`, server-owned). Enacts the client half
/// of the anti-cheat contract:
///   ClipShown     → start-clip (server stamps serverShownAt) + start countdown
///   OptionSelected→ submit-answer (server clamps elapsed, returns the reveal)
///   timeout (0s)  → auto-submit a null answer
///   NextClip      → advance + restart the countdown
///   RoundCompleted→ complete-round (final score, fandom %, rank)
/// The countdown [Timer] is always cancelled in [close] so a popped game can
/// never keep ticking (no ANR / leaked timer).
class GameBloc extends Bloc<GameEvent, GameState> {
  GameBloc({
    required CreateRoundUseCase createRound,
    required StartClipUseCase startClip,
    required SubmitAnswerUseCase submitAnswer,
    required CompleteRoundUseCase completeRound,
  })  : _createRound = createRound,
        _startClip = startClip,
        _submitAnswer = submitAnswer,
        _completeRound = completeRound,
        super(const GameState()) {
    on<RoundStarted>(_onRoundStarted);
    on<ClipShown>(_onClipShown);
    on<OptionSelected>(_onOptionSelected);
    on<GameTimerTicked>(_onTimerTicked);
    on<NextClip>(_onNextClip);
    on<RoundCompleted>(_onRoundCompleted);
  }

  final CreateRoundUseCase _createRound;
  final StartClipUseCase _startClip;
  final SubmitAnswerUseCase _submitAnswer;
  final CompleteRoundUseCase _completeRound;

  Timer? _timer;
  DateTime? _clipShownAt;
  bool _submitting = false;

  Future<void> _onRoundStarted(
    RoundStarted event,
    Emitter<GameState> emit,
  ) async {
    _cancelTimer();
    emit(const GameState(phase: GamePhase.loading));

    // A pre-built round (e.g. joined challenge) skips create_round.
    if (event.round != null) {
      _emitRound(event.round!, emit);
      return;
    }

    final result = await _createRound(
      mode: event.mode,
      actorId: event.actorId,
      kind: event.kind,
    );
    switch (result) {
      case Success<TriviaRoundEntity>(:final value):
        _emitRound(value, emit);
      case Failure<TriviaRoundEntity>(:final error):
        emit(state.copyWith(phase: GamePhase.error, message: _message(error)));
    }
  }

  void _emitRound(TriviaRoundEntity round, Emitter<GameState> emit) {
    // The countdown length comes from the round itself so a server-side change
    // takes effect without shipping a new build.
    final deadlineMs = round.answerWindowMs ?? kFallbackAnswerWindowMs;
    emit(GameState(
      phase: GamePhase.playing,
      roundId: round.roundId,
      mode: round.mode,
      clips: round.clips,
      index: round.index, // resume position for a partially-played round
      timeRemaining: _secondsFor(deadlineMs),
      deadlineMs: deadlineMs,
      score: 0,
      actor: round.actor,
      challengeCode: round.challengeCode,
    ));
    // Drive the first (resume) clip: stamps start-clip and starts the timer.
    add(ClipShown(round.index));
  }

  Future<void> _onClipShown(ClipShown event, Emitter<GameState> emit) async {
    final s = state;
    if (s.phase == GamePhase.finished || s.phase == GamePhase.error) return;
    if (event.clipIndex < 0 || event.clipIndex >= s.clips.length) return;

    _submitting = false;
    _clipShownAt = DateTime.now();
    emit(s.copyWith(
      phase: GamePhase.playing,
      index: event.clipIndex,
      timeRemaining: _secondsFor(s.deadlineMs),
      selectedOptionId: null,
      reveal: null,
      message: null,
    ));
    _startTimer();

    // Stamp the clip as shown server-side. Failure is non-fatal to playback
    // (the submit path clamps elapsed regardless), so it is consumed quietly.
    switch (await _startClip(roundId: s.roundId, clipIndex: event.clipIndex)) {
      case Success<void>():
        break;
      case Failure<void>():
        break; // swallow — the clip keeps playing
    }
  }

  Future<void> _onOptionSelected(
    OptionSelected event,
    Emitter<GameState> emit,
  ) async {
    final s = state;
    if (s.phase != GamePhase.playing || _submitting) return;
    _submitting = true;
    _cancelTimer();

    final elapsedMs = _clipShownAt == null
        ? s.deadlineMs
        : DateTime.now()
            .difference(_clipShownAt!)
            .inMilliseconds
            .clamp(0, s.deadlineMs)
            .toInt();

    // Optimistically lock the chosen chip while the submit is in flight.
    emit(s.copyWith(selectedOptionId: event.optionId));

    final result = await _submitAnswer(
      roundId: s.roundId,
      clipIndex: s.index,
      chosenOptionId: event.optionId,
      clientElapsedMs: elapsedMs,
    );
    _submitting = false;
    final cur = state;
    switch (result) {
      case Success<RevealResultEntity>(:final value):
        emit(cur.copyWith(
          phase: GamePhase.revealed,
          reveal: value,
          score: value.runningScore,
        ));
      case Failure<RevealResultEntity>(:final error):
        // Unlock so the player can retry, and surface the error.
        emit(cur.copyWith(
          phase: GamePhase.playing,
          selectedOptionId: null,
          message: _message(error),
        ));
    }
  }

  void _onTimerTicked(GameTimerTicked event, Emitter<GameState> emit) {
    final s = state;
    if (s.phase != GamePhase.playing) return;
    final next = s.timeRemaining - 1;
    if (next <= 0) {
      _cancelTimer();
      emit(s.copyWith(timeRemaining: 0));
      // Deadline reached → auto-submit an unanswered (null) response.
      add(const OptionSelected(null));
    } else {
      emit(s.copyWith(timeRemaining: next));
    }
  }

  void _onNextClip(NextClip event, Emitter<GameState> emit) {
    final s = state;
    if (s.phase == GamePhase.finished || s.phase == GamePhase.error) return;
    final next = s.index + 1;
    if (next >= s.clips.length) return; // caller dispatches RoundCompleted
    // ClipShown advances the index, restarts the countdown and calls start-clip.
    add(ClipShown(next));
  }

  Future<void> _onRoundCompleted(
    RoundCompleted event,
    Emitter<GameState> emit,
  ) async {
    _cancelTimer();
    final result = await _completeRound(state.roundId);
    switch (result) {
      case Success<TriviaResultEntity>(:final value):
        emit(state.copyWith(phase: GamePhase.finished, result: value));
      case Failure<TriviaResultEntity>(:final error):
        emit(state.copyWith(phase: GamePhase.error, message: _message(error)));
    }
  }

  /// Whole seconds shown on the ring, rounded up so a 10s window starts at 10.
  int _secondsFor(int deadlineMs) => (deadlineMs / 1000).ceil();

  void _startTimer() {
    _cancelTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) add(const GameTimerTicked());
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> close() {
    _cancelTimer();
    return super.close();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
