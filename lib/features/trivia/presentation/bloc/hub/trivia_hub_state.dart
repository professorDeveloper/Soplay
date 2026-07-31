import 'package:equatable/equatable.dart';
import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';

enum TriviaHubStatus { initial, loading, loaded, error }

const Object _unset = Object();

/// Backs the Buff hub: the current user's daily-rank teaser plus the head of
/// today's board. [myDailyRank] is null when the user has not yet placed on
/// today's board (teaser simply hidden); [dailyTop] is empty when nobody has
/// played today.
class TriviaHubState extends Equatable {
  const TriviaHubState({
    this.status = TriviaHubStatus.initial,
    this.myDailyRank,
    this.dailyTop = const <LeaderboardEntryEntity>[],
    this.message,
  });

  final TriviaHubStatus status;
  final LeaderboardEntryEntity? myDailyRank;

  /// Today's leading players, excluding the current user (their own standing is
  /// already the rank card). Comes free with the rank request — the same daily
  /// leaderboard call used to be parsed for one row and thrown away.
  final List<LeaderboardEntryEntity> dailyTop;

  final String? message;

  bool get isRanked => myDailyRank != null;

  TriviaHubState copyWith({
    TriviaHubStatus? status,
    Object? myDailyRank = _unset,
    List<LeaderboardEntryEntity>? dailyTop,
    Object? message = _unset,
  }) {
    return TriviaHubState(
      status: status ?? this.status,
      myDailyRank: myDailyRank == _unset
          ? this.myDailyRank
          : myDailyRank as LeaderboardEntryEntity?,
      dailyTop: dailyTop ?? this.dailyTop,
      message: message == _unset ? this.message : message as String?,
    );
  }

  @override
  List<Object?> get props => [status, myDailyRank, dailyTop, message];
}
