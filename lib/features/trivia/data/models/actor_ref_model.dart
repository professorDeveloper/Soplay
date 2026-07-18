import 'package:soplay/features/trivia/domain/entities/actor_ref_entity.dart';

class ActorRefModel extends ActorRefEntity {
  const ActorRefModel({
    required super.id,
    required super.kind,
    required super.name,
    required super.profileUrl,
  });

  factory ActorRefModel.fromJson(Map<String, dynamic> json) {
    return ActorRefModel(
      id: _int(json['id'] ?? json['actorId']),
      kind: _str(json['kind']),
      name: _str(json['name']),
      profileUrl: _str(
        json['profile'] ?? json['profileUrl'] ?? json['profilePath'],
      ),
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
