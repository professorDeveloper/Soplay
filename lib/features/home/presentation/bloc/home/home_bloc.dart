import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/usecase/home_usecase.dart';

import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final HomeUseCase useCase;

  HomeBloc({required this.useCase}) : super(HomeInitial()) {
    on<HomeLoad>(_onHomeLoad);
  }

  Future<void> _onHomeLoad(HomeLoad event, Emitter<HomeState> emit) async {
    if (!event.silent || state is! HomeLoaded) {
      emit(HomeLoading());
    }

    final genreResult = await useCase.callGenres();
    debugPrint('[HomeBloc] genres: ${genreResult.isSuccess ? 'ok (${genreResult.getOrNull()?.length})' : 'fail'}');
    final result = await useCase();
    debugPrint('[HomeBloc] home: ${result.isSuccess ? 'ok' : 'fail: ${result.getErrorOrNull()}'}');
    switch (result) {
      case Success(:final value):
        debugPrint('[HomeBloc] banner=${value.banner.length} sections=${value.sections.length}');
        emit(HomeLoaded(genreResult.getOrNull() ?? [], value));
      case Failure(:final error):
        emit(HomeError(error.toString()));
    }
  }
}
