import 'package:soplay/features/trivia/data/models/top_fan_model.dart';
import 'package:soplay/features/trivia/domain/entities/actor_fan_stat_entity.dart';

class ActorFanStatModel extends ActorFanStatEntity {
  const ActorFanStatModel({
    required super.actorId,
    required super.kind,
    required super.name,
    required super.profileUrl,
    required super.roundsPlayed,
    required super.avgFandom,
    required super.topFans,
  });

  factory ActorFanStatModel.fromJson(Map<String, dynamic> json) {
    final rawFans = json['topFans'] ?? json['fans'] ?? json['items'];
    final fans = rawFans is List
        ? rawFans
            .whereType<Map>()
            .toList()
            .asMap()
            .entries
            .map((entry) {
              final m = entry.value.cast<String, dynamic>();
              // Fall back to positional rank when the server omits one.
              return TopFanModel.fromJson({'rank': entry.key + 1, ...m});
            })
            .toList(growable: false)
        : const <TopFanModel>[];

    return ActorFanStatModel(
      actorId: _int(json['actorId'] ?? json['id']),
      kind: _str(json['kind']),
      name: _str(json['name']),
      profileUrl: _str(json['profile'] ?? json['profileUrl']),
      roundsPlayed: _int(json['roundsPlayed']),
      avgFandom: _double(json['avgFandom']),
      topFans: fans,
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
