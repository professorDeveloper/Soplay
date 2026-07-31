import 'package:equatable/equatable.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';

/// - [initial]        nothing loaded yet
/// - [loadingPopular] fetching the popular grid (empty query)
/// - [popular]        showing the popular grid
/// - [searching]      a debounced query is in flight
/// - [results]        showing as-you-type search results
/// - [empty]          a search returned no matches
/// - [error]          the last load/search failed
enum CastStatus { initial, loadingPopular, popular, searching, results, empty, error }

class CastState extends Equatable {
  const CastState({
    this.kind = 'person',
    this.query = '',
    this.status = CastStatus.initial,
    this.popular = const <CastPersonEntity>[],
    this.results = const <CastPersonEntity>[],
    this.message,
  });

  final String kind; // 'person' (Movies) | 'character' (Anime)
  final String query;
  final CastStatus status;
  final List<CastPersonEntity> popular;
  final List<CastPersonEntity> results;
  final String? message;

  /// Whether the UI should render the results list rather than the popular grid.
  bool get isSearchActive => query.isNotEmpty;

  CastState copyWith({
    String? kind,
    String? query,
    CastStatus? status,
    List<CastPersonEntity>? popular,
    List<CastPersonEntity>? results,
    String? message,
    bool clearMessage = false,
  }) {
    return CastState(
      kind: kind ?? this.kind,
      query: query ?? this.query,
      status: status ?? this.status,
      popular: popular ?? this.popular,
      results: results ?? this.results,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [kind, query, status, popular, results, message];
}
