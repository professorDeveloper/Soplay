import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';
import 'package:soplay/features/trivia/domain/usecases/get_leaderboard_usecase.dart';

import 'trivia_hub_event.dart';
import 'trivia_hub_state.dart';

/// Loads the hub's daily-rank teaser by reading the daily leaderboard and
/// pulling out the current user's own row. The mode-select cards themselves are
/// static UI; a teaser failure keeps the hub usable rather than blocking it.
class TriviaHubBloc extends Bloc<TriviaHubEvent, TriviaHubState> {
  TriviaHubBloc({required GetLeaderboardUseCase getLeaderboard})
      : _getLeaderboard = getLeaderboard,
        super(const TriviaHubState()) {
    on<TriviaHubStarted>(_onLoad);
    on<TriviaHubRefreshed>(_onLoad);
  }

  final GetLeaderboardUseCase _getLeaderboard;

  Future<void> _onLoad(
    TriviaHubEvent event,
    Emitter<TriviaHubState> emit,
  ) async {
    emit(state.copyWith(status: TriviaHubStatus.loading, message: null));
    final result = await _getLeaderboard(scope: 'daily');
    switch (result) {
      case Success<List<LeaderboardEntryEntity>>(:final value):
        emit(state.copyWith(
          status: TriviaHubStatus.loaded,
          myDailyRank: _mine(value),
        ));
      case Failure<List<LeaderboardEntryEntity>>(:final error):
        // The rank teaser is non-critical: keep the mode cards on screen and
        // surface the failure quietly instead of showing a full-screen error.
        emit(state.copyWith(
          status: TriviaHubStatus.loaded,
          myDailyRank: null,
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
