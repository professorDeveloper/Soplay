import 'package:soplay/features/trivia/domain/entities/top_fan_entity.dart';

class TopFanModel extends TopFanEntity {
  const TopFanModel({
    required super.rank,
    required super.userId,
    required super.username,
    required super.avatar,
    required super.bestScore,
    required super.bestFandom,
    required super.updatedAt,
  });

  factory TopFanModel.fromJson(Map<String, dynamic> json) {
    return TopFanModel(
      rank: _int(json['rank']),
      userId: _str(json['userId'] ?? json['_id']),
      username: _str(json['username']),
      avatar: _str(json['avatar']),
      bestScore: _int(json['bestScore'] ?? json['score']),
      bestFandom: _double(json['bestFandom'] ?? json['fandomPercent']),
      updatedAt: _str(json['updatedAt']),
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
