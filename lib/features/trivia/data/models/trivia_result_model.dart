import 'package:riasdxd/features/trivia/domain/entities/trivia_result_entity.dart';

class TriviaResultModel extends TriviaResultEntity {
  const TriviaResultModel({
    required super.score,
    required super.fandomPercent,
    required super.rank,
    required super.correctCount,
    required super.totalClips,
  });

  factory TriviaResultModel.fromJson(Map<String, dynamic> json) {
    return TriviaResultModel(
      score: _int(json['score'] ?? json['totalScore']),
      fandomPercent: _double(json['fandomPercent']),
      rank: _int(json['rank']),
      correctCount: _int(json['correctCount']),
      // Absent on a legacy payload → 0, which the UI reads as "hide the
      // denominator". Defaulting to correctCount would claim a perfect round.
      totalClips: _int(json['totalClips'] ?? json['clipCount']),
    );
  }

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
