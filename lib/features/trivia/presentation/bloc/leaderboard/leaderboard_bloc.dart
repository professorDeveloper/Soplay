import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:riasdxd/features/trivia/domain/usecases/get_leaderboard_usecase.dart';

import 'leaderboard_event.dart';
import 'leaderboard_state.dart';

/// Leaderboard with daily / weekly / all-time / friends scope tabs. Pulls the
/// current user's own row out of the results as [LeaderboardState.myRank] so
/// the UI can pin / highlight it.
class LeaderboardBloc extends Bloc<LeaderboardEvent, LeaderboardState> {
  LeaderboardBloc({required GetLeaderboardUseCase getLeaderboard})
      : _getLeaderboard = getLeaderboard,
        super(const LeaderboardState()) {
    on<LeaderboardStarted>(_onStarted);
    on<LeaderboardScopeChanged>(_onScopeChanged);
    on<LeaderboardRefreshed>(_onRefreshed);
  }

  final GetLeaderboardUseCase _getLeaderboard;

  Future<void> _onStarted(
    LeaderboardStarted event,
    Emitter<LeaderboardState> emit,
  ) async {
    emit(state.copyWith(
      scope: event.scope,
      mode: event.mode,
      actorId: event.actorId,
    ));
    await _load(emit);
  }

  Future<void> _onScopeChanged(
    LeaderboardScopeChanged event,
    Emitter<LeaderboardState> emit,
  ) async {
    emit(state.copyWith(scope: event.scope));
    await _load(emit);
  }

  Future<void> _onRefreshed(
    LeaderboardRefreshed event,
    Emitter<LeaderboardState> emit,
  ) =>
      _load(emit);

  Future<void> _load(Emitter<LeaderboardState> emit) async {
    emit(state.copyWith(status: LeaderboardStatus.loading, message: null));
    final result = await _getLeaderboard(
      scope: state.scope,
      mode: state.mode,
      actorId: state.actorId,
    );
    switch (result) {
      case Success<List<LeaderboardEntryEntity>>(:final value):
        emit(state.copyWith(
          status: LeaderboardStatus.loaded,
          entries: value,
          myRank: _mine(value),
        ));
      case Failure<List<LeaderboardEntryEntity>>(:final error):
        emit(state.copyWith(
          status: LeaderboardStatus.error,
          message: _message(error),
        ));
    }
  }

  LeaderboardEntryEntity? _mine(List<LeaderboardEntryEntity> entries) {
    for (final entry in entries) {
      if (entry.isMe) return entry;
    }
    return null;
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
