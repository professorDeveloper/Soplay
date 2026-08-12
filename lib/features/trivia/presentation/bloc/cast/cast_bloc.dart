import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:riasdxd/features/trivia/domain/usecases/get_popular_cast_usecase.dart';
import 'package:riasdxd/features/trivia/domain/usecases/search_cast_usecase.dart';

import 'cast_event.dart';
import 'cast_state.dart';

/// Cast picker: a "Popular now" grid on an empty query, 300ms-debounced
/// search-as-you-type, and a Movies(person)/Anime(character) kind toggle.
///
/// Debounce + "latest wins" (restartable) are implemented with a monotonic
/// [_token]: every keystroke, kind switch, or popular reload bumps the token,
/// and any in-flight handler whose token has gone stale drops its result before
/// it can emit. This mirrors the Timer/token pattern already used by SearchBloc
/// — the project has no `bloc_concurrency` dependency to supply `restartable()`.
class CastBloc extends Bloc<CastEvent, CastState> {
  CastBloc({
    required SearchCastUseCase searchCast,
    required GetPopularCastUseCase getPopularCast,
  })  : _searchCast = searchCast,
        _getPopularCast = getPopularCast,
        super(const CastState()) {
    on<CastStarted>(_onStarted);
    on<CastKindChanged>(_onKindChanged);
    on<CastQueryChanged>(_onQueryChanged);
    on<CastCleared>(_onCleared);
  }

  final SearchCastUseCase _searchCast;
  final GetPopularCastUseCase _getPopularCast;

  static const Duration _debounce = Duration(milliseconds: 300);
  int _token = 0;

  Future<void> _onStarted(CastStarted event, Emitter<CastState> emit) =>
      _loadPopular(emit);

  Future<void> _onKindChanged(
    CastKindChanged event,
    Emitter<CastState> emit,
  ) async {
    if (event.kind == state.kind) return;
    emit(state.copyWith(kind: event.kind));
    if (state.query.isEmpty) {
      await _loadPopular(emit);
    } else {
      // A toggle is a deliberate action — re-run the search immediately.
      await _runSearch(state.query, emit, immediate: true);
    }
  }

  Future<void> _onQueryChanged(
    CastQueryChanged event,
    Emitter<CastState> emit,
  ) async {
    final query = event.query.trim();
    emit(state.copyWith(query: query));
    if (query.isEmpty) {
      await _loadPopular(emit);
      return;
    }
    await _runSearch(query, emit);
  }

  Future<void> _onCleared(CastCleared event, Emitter<CastState> emit) async {
    emit(state.copyWith(query: ''));
    await _loadPopular(emit);
  }

  Future<void> _loadPopular(Emitter<CastState> emit) async {
    final token = ++_token;
    emit(state.copyWith(status: CastStatus.loadingPopular, clearMessage: true));
    final result = await _getPopularCast(kind: state.kind);
    if (token != _token || isClosed) return; // superseded by a newer action
    switch (result) {
      case Success<List<CastPersonEntity>>(:final value):
        emit(state.copyWith(status: CastStatus.popular, popular: value));
      case Failure<List<CastPersonEntity>>(:final error):
        emit(state.copyWith(status: CastStatus.error, message: _message(error)));
    }
  }

  Future<void> _runSearch(
    String query,
    Emitter<CastState> emit, {
    bool immediate = false,
  }) async {
    final token = ++_token;
    emit(state.copyWith(status: CastStatus.searching, clearMessage: true));
    if (!immediate) {
      await Future<void>.delayed(_debounce);
      if (token != _token || isClosed) return; // a newer keystroke won
    }
    final result = await _searchCast(query: query, kind: state.kind);
    if (token != _token || isClosed) return; // superseded while awaiting network
    switch (result) {
      case Success<List<CastPersonEntity>>(:final value):
        emit(state.copyWith(
          status: value.isEmpty ? CastStatus.empty : CastStatus.results,
          results: value,
        ));
      case Failure<List<CastPersonEntity>>(:final error):
        emit(state.copyWith(status: CastStatus.error, message: _message(error)));
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
