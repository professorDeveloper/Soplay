import 'package:equatable/equatable.dart';
import 'package:riasdxd/features/trivia/domain/entities/leaderboard_entry_entity.dart';

enum LeaderboardStatus { initial, loading, loaded, error }

const Object _unset = Object();

class LeaderboardState extends Equatable {
  const LeaderboardState({
    this.scope = 'daily',
    this.status = LeaderboardStatus.initial,
    this.entries = const <LeaderboardEntryEntity>[],
    this.myRank,
    this.mode,
    this.actorId,
    this.message,
  });

  final String scope; // daily | weekly | all | friends
  final LeaderboardStatus status;
  final List<LeaderboardEntryEntity> entries;

  /// The current user's own row (pulled out of [entries]) so it can be pinned /
  /// highlighted. Null when the user is not on this board.
  final LeaderboardEntryEntity? myRank;

  final String? mode;
  final int? actorId;
  final String? message;

  LeaderboardState copyWith({
    String? scope,
    LeaderboardStatus? status,
    List<LeaderboardEntryEntity>? entries,
    Object? myRank = _unset,
    Object? mode = _unset,
    Object? actorId = _unset,
    Object? message = _unset,
  }) {
    return LeaderboardState(
      scope: scope ?? this.scope,
      status: status ?? this.status,
      entries: entries ?? this.entries,
      myRank: myRank == _unset ? this.myRank : myRank as LeaderboardEntryEntity?,
      mode: mode == _unset ? this.mode : mode as String?,
      actorId: actorId == _unset ? this.actorId : actorId as int?,
      message: message == _unset ? this.message : message as String?,
    );
  }

  @override
  List<Object?> get props =>
      [scope, status, entries, myRank, mode, actorId, message];
}
