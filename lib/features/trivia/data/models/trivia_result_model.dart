import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';

class TriviaResultModel extends TriviaResultEntity {
  const TriviaResultModel({
    required super.score,
    required super.fandomPercent,
    required super.rank,
    required super.correctCount,
  });

  factory TriviaResultModel.fromJson(Map<String, dynamic> json) {
    return TriviaResultModel(
      score: _int(json['score'] ?? json['totalScore']),
      fandomPercent: _double(json['fandomPercent']),
      rank: _int(json['rank']),
      correctCount: _int(json['correctCount']),
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
