import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/challenge_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';
import 'package:soplay/features/trivia/domain/usecases/get_challenge_usecase.dart';
import 'package:soplay/features/trivia/domain/usecases/join_challenge_usecase.dart';

import 'challenge_event.dart';
import 'challenge_state.dart';

/// Challenge landing page: load a challenge by code (get_challenge) and join it
/// (join_challenge) to obtain a round built from the frozen 10 clips. The joined
/// [ChallengeState.round] is handed off to the game.
class ChallengeBloc extends Bloc<ChallengeEvent, ChallengeState> {
  ChallengeBloc({
    required GetChallengeUseCase getChallenge,
    required JoinChallengeUseCase joinChallenge,
  })  : _getChallenge = getChallenge,
        _joinChallenge = joinChallenge,
        super(const ChallengeState()) {
    on<ChallengeOpened>(_onOpened);
    on<ChallengeJoined>(_onJoined);
  }

  final GetChallengeUseCase _getChallenge;
  final JoinChallengeUseCase _joinChallenge;

  Future<void> _onOpened(
    ChallengeOpened event,
    Emitter<ChallengeState> emit,
  ) async {
    emit(state.copyWith(status: ChallengeStatus.loading, message: null));
    final result = await _getChallenge(event.code);
    switch (result) {
      case Success<ChallengeEntity>(:final value):
        emit(state.copyWith(status: ChallengeStatus.loaded, challenge: value));
      case Failure<ChallengeEntity>(:final error):
        emit(state.copyWith(
          status: ChallengeStatus.error,
          message: _message(error),
        ));
    }
  }

  Future<void> _onJoined(
    ChallengeJoined event,
    Emitter<ChallengeState> emit,
  ) async {
    // Keep any already-loaded challenge meta visible while joining.
    emit(state.copyWith(status: ChallengeStatus.joining, message: null));
    final result = await _joinChallenge(event.code);
    switch (result) {
      case Success<TriviaRoundEntity>(:final value):
        emit(state.copyWith(status: ChallengeStatus.joined, round: value));
      case Failure<TriviaRoundEntity>(:final error):
        emit(state.copyWith(
          status: ChallengeStatus.error,
          message: _message(error),
        ));
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
