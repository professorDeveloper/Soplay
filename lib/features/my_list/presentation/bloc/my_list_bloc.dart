import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/my_list/domain/entities/my_list_failure.dart';
import 'package:soplay/features/my_list/domain/usecases/get_favorites_usecase.dart';

import 'my_list_event.dart';
import 'my_list_state.dart';

class MyListBloc extends Bloc<MyListEvent, MyListState> {
  final GetFavoritesUseCase useCase;
  final PrivateListService _private;

  MyListBloc({required this.useCase, PrivateListService? private})
      : _private = private ?? getIt<PrivateListService>(),
        super(const MyListInitial()) {
    on<MyListLoad>(_onLoad);
    on<MyListRefresh>(_onRefresh);
  }

  Future<void> _onLoad(MyListLoad event, Emitter<MyListState> emit) async {
    emit(const MyListLoading());
    await _load(emit);
  }

  Future<void> _onRefresh(
    MyListRefresh event,
    Emitter<MyListState> emit,
  ) async {
    final current = state;
    if (current is MyListLoaded) {
      emit(current.copyWith(refreshing: true));
    } else {
      emit(const MyListLoading());
    }
    await _load(emit);
  }

  Future<void> _load(Emitter<MyListState> emit) async {
    final result = await useCase();
    switch (result) {
      case Success<List<FavoriteEntity>>(:final value):
        final privateUrls =
            _private.getAll().map((e) => e.contentUrl).toSet();
        final visible = privateUrls.isEmpty
            ? value
            : value
                .where((e) => !privateUrls.contains(e.contentUrl))
                .toList();
        emit(MyListLoaded(items: visible));
      case Failure<List<FavoriteEntity>>(:final error):
        if (error is MyListUnauthorizedException) {
          emit(const MyListUnauthorized());
          return;
        }
        emit(MyListError(_friendlyError(error)));
    }
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }
}
