import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/data/search_recents_store.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';
import 'package:soplay/features/search/domain/usecases/genre_usecase.dart';
import 'package:soplay/features/search/domain/usecases/search_usecase.dart';
import 'package:soplay/features/search/presentation/blocs/search_query_policy.dart';

part 'search_event.dart';
part 'search_state.dart';

/// Single-source search.
///
/// Every handler that awaits carries the run token: a response that lands after
/// a newer run has started is dropped instead of overwriting it. Genres are a
/// field on the state, not a state of their own, so a failed genres fetch can
/// never repaint the results as a network error.
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchUseCase _searchUseCase;
  final GenreUseCase _genreUseCase;
  final SearchRecentsStore _recents;

  final QueryDebouncer _debouncer = QueryDebouncer();

  int _runToken = 0;
  int _genreToken = 0;

  /// What is in the box right now. Kept off the state on purpose: a keystroke
  /// must not rebuild the results grid.
  String _pendingText = '';

  SearchBloc({
    required SearchUseCase searchUseCase,
    required GenreUseCase genreUseCase,
    SearchRecentsStore? recentsStore,
  })  : _searchUseCase = searchUseCase,
        _genreUseCase = genreUseCase,
        _recents = recentsStore ?? SearchRecentsStore(),
        super(const SearchState()) {
    on<SearchLoad>(_onLoad);
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchSubmitted>(_onSubmitted);
    on<SearchGenreSelected>(_onGenreSelected);
    on<_SearchRun>(_onRun);
    on<SearchLoadMore>(_onLoadMore);
    on<SearchRetry>(_onRetry);
    on<SearchRecentRemoved>(_onRecentRemoved);
    on<SearchRecentsCleared>(_onRecentsCleared);

    add(const SearchLoad());
  }

  Future<void> _onLoad(SearchLoad event, Emitter<SearchState> emit) async {
    final genreToken = ++_genreToken;
    ++_runToken;
    _debouncer.reset();

    // Genres belong to the provider that is being left behind, and so do the
    // results; the text in the box does not.
    final criteria = SearchCriteria(text: state.criteria.text);
    emit(state.copyWith(
      criteria: criteria,
      status: criteria.isEmpty ? SearchStatus.idle : SearchStatus.loading,
      items: const [],
      page: 1,
      totalPages: 1,
      isLoadingMore: false,
      genres: const [],
      genresLoading: true,
      genresFailed: false,
      recent: _recents.load(),
      clearError: true,
    ));

    if (criteria.isNotEmpty) add(_SearchRun(criteria));

    final result = await _genreUseCase();
    if (genreToken != _genreToken || isClosed) return;
    emit(state.copyWith(
      genres: result.isSuccess ? result.getOrNull()! : const [],
      genresLoading: false,
      genresFailed: result.isError,
    ));
  }

  void _onQueryChanged(SearchQueryChanged event, Emitter<SearchState> emit) {
    final q = SearchQueryPolicy.normalize(event.query);
    _pendingText = q;

    if (q.isEmpty) {
      _debouncer.reset();
      ++_runToken;
      final criteria = state.criteria.copyWith(text: '');
      if (criteria.isEmpty) {
        emit(state.copyWith(
          criteria: criteria,
          status: SearchStatus.idle,
          items: const [],
          page: 1,
          totalPages: 1,
          isLoadingMore: false,
          recent: _recents.load(),
          clearError: true,
        ));
      } else {
        add(_SearchRun(criteria));
      }
      return;
    }

    _debouncer.schedule(q, (value) {
      if (isClosed) return;
      // Same reason as _onGenreSelected: the two cannot be combined, so the
      // one the user just acted on wins.
      add(_SearchRun(SearchCriteria(text: value, genre: '')));
    });
  }

  void _onSubmitted(SearchSubmitted event, Emitter<SearchState> emit) {
    _pendingText = SearchQueryPolicy.normalize(event.query);
    _debouncer.runNow(_pendingText, (value) {
      if (isClosed) return;
      add(_SearchRun(state.criteria.copyWith(text: value)));
    });
  }

  void _onGenreSelected(SearchGenreSelected event, Emitter<SearchState> emit) {
    _debouncer.reset();
    // Genre and text do not compose: the server's /contents/search takes only
    // q, page and provider, so a genre sent alongside a query is dropped on the
    // floor and the user gets a plain text search under an active filter chip.
    // Picking a genre therefore browses that genre instead.
    final genre = event.genre.trim();
    if (genre.isNotEmpty) _pendingText = '';
    final text = genre.isNotEmpty
        ? ''
        : (SearchQueryPolicy.runnable(_pendingText) ? _pendingText : '');
    final criteria = SearchCriteria(text: text, genre: genre);
    if (criteria.isEmpty) {
      ++_runToken;
      emit(state.copyWith(
        criteria: criteria,
        status: SearchStatus.idle,
        items: const [],
        page: 1,
        totalPages: 1,
        isLoadingMore: false,
        recent: _recents.load(),
        clearError: true,
      ));
      return;
    }
    add(_SearchRun(criteria));
  }

  Future<void> _onRun(_SearchRun event, Emitter<SearchState> emit) async {
    final token = ++_runToken;
    final criteria = event.criteria;

    // Something is already on screen: keep it and show progress on top of it
    // rather than blanking the grid on every keystroke.
    final keepItems = state.items.isNotEmpty;
    emit(state.copyWith(
      criteria: criteria,
      status: keepItems ? SearchStatus.refreshing : SearchStatus.loading,
      isLoadingMore: false,
      clearError: true,
    ));

    final result = await _fetch(criteria, 1);
    if (token != _runToken || isClosed) return;

    if (result.isError) {
      final raw = result.getErrorOrNull()!.toString();
      _debouncer.forget();
      emit(state.copyWith(
        status: SearchStatus.error,
        items: const [],
        page: 1,
        totalPages: 1,
        errorMessage: cleanFailureMessage(raw),
        errorKind: classifySearchFailure(raw),
      ));
      return;
    }

    final data = result.getOrNull()!;
    final recent = criteria.text.isEmpty
        ? state.recent
        : await _recents.add(criteria.text);
    if (token != _runToken || isClosed) return;

    emit(state.copyWith(
      items: data.items,
      page: data.page,
      totalPages: data.totalPages,
      status: data.items.isEmpty ? SearchStatus.empty : SearchStatus.loaded,
      recent: recent,
      clearError: true,
    ));
  }

  Future<void> _onLoadMore(
    SearchLoadMore event,
    Emitter<SearchState> emit,
  ) async {
    if (state.status != SearchStatus.loaded ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }

    final token = ++_runToken;
    final criteria = state.criteria;
    final nextPage = state.page + 1;
    emit(state.copyWith(isLoadingMore: true));

    final result = await _fetch(criteria, nextPage);
    if (token != _runToken || isClosed) return;

    if (result.isError) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final data = result.getOrNull()!;
    final seen = {for (final m in state.items) '${m.provider}::${m.url}'};
    final fresh = <MovieEntity>[
      for (final m in data.items)
        if (seen.add('${m.provider}::${m.url}')) m,
    ];
    emit(state.copyWith(
      items: [...state.items, ...fresh],
      page: data.page,
      totalPages: data.totalPages,
      isLoadingMore: false,
    ));
  }

  void _onRetry(SearchRetry event, Emitter<SearchState> emit) {
    _debouncer.reset();
    if (state.criteria.isEmpty) {
      add(const SearchLoad());
      return;
    }
    add(_SearchRun(state.criteria));
  }

  Future<void> _onRecentRemoved(
    SearchRecentRemoved event,
    Emitter<SearchState> emit,
  ) async {
    final recent = await _recents.remove(event.query);
    if (isClosed) return;
    emit(state.copyWith(recent: recent));
  }

  Future<void> _onRecentsCleared(
    SearchRecentsCleared event,
    Emitter<SearchState> emit,
  ) async {
    final recent = await _recents.clear();
    if (isClosed) return;
    emit(state.copyWith(recent: recent));
  }

  Future<Result<SearchEntity>> _fetch(SearchCriteria criteria, int page) {
    if (criteria.text.isNotEmpty) {
      return _searchUseCase(criteria.text, page: page);
    }
    return _genreUseCase.callByGenre(criteria.genre, page: page);
  }

  @override
  Future<void> close() {
    _debouncer.dispose();
    return super.close();
  }
}
