import 'package:soplay/features/trivia/domain/entities/leaderboard_entry_entity.dart';

class LeaderboardEntryModel extends LeaderboardEntryEntity {
  const LeaderboardEntryModel({
    required super.rank,
    required super.userId,
    required super.username,
    required super.avatar,
    required super.score,
    required super.correctCount,
    required super.totalTimeMs,
    required super.fandomPercent,
    required super.isMe,
  });

  factory LeaderboardEntryModel.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntryModel(
      rank: _int(json['rank']),
      userId: _str(json['userId'] ?? json['_id']),
      username: _str(json['username']),
      avatar: _str(json['avatar']),
      score: _int(json['score'] ?? json['totalScore']),
      correctCount: _int(json['correctCount']),
      totalTimeMs: _int(json['totalTimeMs'] ?? json['totalTime']),
      fandomPercent: _double(json['fandomPercent']),
      isMe: _bool(json['isMe']),
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

  static bool _bool(dynamic v) {
    if (v is bool) return v;
    final raw = v?.toString().toLowerCase();
    return raw == 'true' || raw == '1';
  }
}
