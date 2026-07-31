import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/trivia/domain/entities/actor_fan_stat_entity.dart';
import 'package:soplay/features/trivia/domain/usecases/get_top_fans_usecase.dart';

import 'top_fans_event.dart';
import 'top_fans_state.dart';

/// Ranked fans of an actor/character — powers the full Top Fans board and the
/// Actor Hero preview strip.
class TopFansBloc extends Bloc<TopFansEvent, TopFansState> {
  TopFansBloc({required GetTopFansUseCase getTopFans})
      : _getTopFans = getTopFans,
        super(const TopFansState()) {
    on<TopFansRequested>(_onRequested);
  }

  final GetTopFansUseCase _getTopFans;

  Future<void> _onRequested(
    TopFansRequested event,
    Emitter<TopFansState> emit,
  ) async {
    emit(state.copyWith(status: TopFansStatus.loading, message: null));
    final result = await _getTopFans(actorId: event.actorId, kind: event.kind);
    switch (result) {
      case Success<ActorFanStatEntity>(:final value):
        emit(state.copyWith(status: TopFansStatus.loaded, fanStat: value));
      case Failure<ActorFanStatEntity>(:final error):
        emit(state.copyWith(
          status: TopFansStatus.error,
          message: _message(error),
        ));
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
