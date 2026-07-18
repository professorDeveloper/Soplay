import 'package:equatable/equatable.dart';

/// A single leaderboard row (daily / weekly / all-time / friends). [isMe]
/// flags the current user's row so it can be pinned / highlighted.
class LeaderboardEntryEntity extends Equatable {
  const LeaderboardEntryEntity({
    required this.rank,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.score,
    required this.correctCount,
    required this.totalTimeMs,
    required this.fandomPercent,
    required this.isMe,
  });

  final int rank;
  final String userId;
  final String username;
  final String avatar;
  final int score;
  final int correctCount;
  final int totalTimeMs;
  final double fandomPercent;
  final bool isMe;

  @override
  List<Object?> get props => [
        rank,
        userId,
        username,
        avatar,
        score,
        correctCount,
        totalTimeMs,
        fandomPercent,
        isMe,
      ];
}
