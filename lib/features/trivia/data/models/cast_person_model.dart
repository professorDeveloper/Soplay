import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';

class CastPersonModel extends CastPersonEntity {
  const CastPersonModel({
    required super.id,
    required super.name,
    required super.profileUrl,
    required super.knownFor,
    required super.kind,
  });

  factory CastPersonModel.fromJson(Map<String, dynamic> json) {
    return CastPersonModel(
      id: _int(json['id'] ?? json['personId'] ?? json['anilistCharId']),
      name: _str(json['name']),
      profileUrl: _str(
        json['profileUrl'] ??
            json['profilePath'] ??
            json['profile'] ??
            json['image'],
      ),
      knownFor: _strList(json['knownFor'] ?? json['media']),
      kind: _str(json['kind']),
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<String> _strList(dynamic v) {
    if (v is! List) return const <String>[];
    return v
        .map((e) {
          if (e is Map) return _str(e['title'] ?? e['name']);
          return _str(e);
        })
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}
