import 'package:soplay/features/trivia/domain/entities/reveal_result_entity.dart';

class RevealResultModel extends RevealResultEntity {
  const RevealResultModel({
    required super.correct,
    required super.correctTmdbId,
    required super.correctTitle,
    required super.poster,
    required super.points,
    required super.runningScore,
    required super.contentUrl,
  });

  factory RevealResultModel.fromJson(Map<String, dynamic> json) {
    return RevealResultModel(
      correct: _bool(json['correct']),
      correctTmdbId: _int(json['correctTmdbId'] ?? json['tmdbId']),
      correctTitle: _str(json['title'] ?? json['correctTitle']),
      poster: _str(json['poster'] ?? json['posterUrl']),
      points: _int(json['points']),
      runningScore: _int(
        json['runningScore'] ?? json['totalScore'] ?? json['score'],
      ),
      contentUrl: _str(json['contentUrl']),
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static bool _bool(dynamic v) {
    if (v is bool) return v;
    final raw = v?.toString().toLowerCase();
    return raw == 'true' || raw == '1';
  }
}
