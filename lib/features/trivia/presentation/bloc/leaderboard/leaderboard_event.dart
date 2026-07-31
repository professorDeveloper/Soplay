import 'package:equatable/equatable.dart';

sealed class LeaderboardEvent extends Equatable {
  const LeaderboardEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load. [scope] is one of daily | weekly | all | friends; [mode] and
/// [actorId] optionally narrow the board (e.g. a per-actor fan-test board).
class LeaderboardStarted extends LeaderboardEvent {
  const LeaderboardStarted({this.scope = 'daily', this.mode, this.actorId});

  final String scope;
  final String? mode;
  final int? actorId;

  @override
  List<Object?> get props => [scope, mode, actorId];
}

/// A scope tab tap (daily / weekly / all / friends).
class LeaderboardScopeChanged extends LeaderboardEvent {
  const LeaderboardScopeChanged(this.scope);

  final String scope;

  @override
  List<Object?> get props => [scope];
}

/// Re-fetch the current scope.
class LeaderboardRefreshed extends LeaderboardEvent {
  const LeaderboardRefreshed();
}
