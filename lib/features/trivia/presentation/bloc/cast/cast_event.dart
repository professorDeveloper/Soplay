import 'package:equatable/equatable.dart';

sealed class CastEvent extends Equatable {
  const CastEvent();

  @override
  List<Object?> get props => [];
}

/// Initial entry to the picker — loads the "Popular now" grid for the current
/// [CastState.kind].
class CastStarted extends CastEvent {
  const CastStarted();
}

/// The Movies / Anime segmented toggle: 'person' (TMDB people) vs 'character'
/// (AniList characters).
class CastKindChanged extends CastEvent {
  const CastKindChanged(this.kind);

  final String kind; // 'person' | 'character'

  @override
  List<Object?> get props => [kind];
}

/// A keystroke in the search box. Debounced (300ms) and restartable downstream:
/// only the latest query survives to hit the network.
class CastQueryChanged extends CastEvent {
  const CastQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// The clear (×) button — drops the query and returns to the popular grid.
class CastCleared extends CastEvent {
  const CastCleared();
}
