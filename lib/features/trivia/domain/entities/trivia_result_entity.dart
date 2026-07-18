import 'package:equatable/equatable.dart';

/// Final round outcome returned by complete-round: total score, fandom %,
/// leaderboard rank and correct-answer count.
class TriviaResultEntity extends Equatable {
  const TriviaResultEntity({
    required this.score,
    required this.fandomPercent,
    required this.rank,
    required this.correctCount,
  });

  final int score;
  final double fandomPercent;
  final int rank;
  final int correctCount;

  @override
  List<Object?> get props => [score, fandomPercent, rank, correctCount];
}
