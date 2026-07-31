import 'package:equatable/equatable.dart';

sealed class TopFansEvent extends Equatable {
  const TopFansEvent();

  @override
  List<Object?> get props => [];
}

/// Load the ranked fans for an actor/character.
class TopFansRequested extends TopFansEvent {
  const TopFansRequested({required this.actorId, required this.kind});

  final int actorId;
  final String kind; // 'person' | 'character'

  @override
  List<Object?> get props => [actorId, kind];
}
