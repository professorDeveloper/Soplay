import 'package:equatable/equatable.dart';

/// Final round outcome returned by complete-round: total score, fandom %,
/// leaderboard rank, correct-answer count and how long the round actually was.
class TriviaResultEntity extends Equatable {
  const TriviaResultEntity({
    required this.score,
    required this.fandomPercent,
    required this.rank,
    required this.correctCount,
    required this.totalClips,
  });

  final int score;
  final double fandomPercent;
  final int rank;
  final int correctCount;

  /// Clips in the round that produced this result. A round is not always 10
  /// clips long — an actor with few approved clips yields a shorter one — so
  /// the denominator is never hardcoded. 0 means the server did not say, in
  /// which case the denominator is hidden rather than guessed.
  final int totalClips;

  /// Whether a "x / y" denominator can honestly be shown.
  bool get hasTotal => totalClips > 0;

  @override
  List<Object?> get props =>
      [score, fandomPercent, rank, correctCount, totalClips];
}
