import 'package:equatable/equatable.dart';
import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';

enum TriviaHubStatus { initial, loading, loaded, error }

const Object _unset = Object();

/// Backs the KINO BILLAR hub: the (static) mode-select cards plus the current
/// user's daily-rank teaser. [myDailyRank] is null when the user has not yet
/// placed on today's board (teaser simply hidden).
class TriviaHubState extends Equatable {
  const TriviaHubState({
    this.status = TriviaHubStatus.initial,
    this.myDailyRank,
    this.message,
  });

  final TriviaHubStatus status;
  final LeaderboardEntryEntity? myDailyRank;
  final String? message;

  bool get isRanked => myDailyRank != null;

  TriviaHubState copyWith({
    TriviaHubStatus? status,
    Object? myDailyRank = _unset,
    Object? message = _unset,
  }) {
    return TriviaHubState(
      status: status ?? this.status,
      myDailyRank: myDailyRank == _unset
          ? this.myDailyRank
          : myDailyRank as LeaderboardEntryEntity?,
      message: message == _unset ? this.message : message as String?,
    );
  }

  @override
  List<Object?> get props => [status, myDailyRank, message];
}
