import 'package:equatable/equatable.dart';

/// The reveal payload returned by the server once an answer is submitted:
/// whether the pick was correct, the real title/poster, the points earned and
/// the running score — plus the re-resolvable [contentUrl] for "Watch full".
class RevealResultEntity extends Equatable {
  const RevealResultEntity({
    required this.correct,
    required this.correctTmdbId,
    required this.correctTitle,
    required this.poster,
    required this.points,
    required this.runningScore,
    required this.contentUrl,
  });

  final bool correct;
  final int correctTmdbId;
  final String correctTitle;
  final String poster;
  final int points;
  final int runningScore;
  final String contentUrl;

  @override
  List<Object?> get props =>
      [correct, correctTmdbId, correctTitle, poster, points, runningScore, contentUrl];
}
