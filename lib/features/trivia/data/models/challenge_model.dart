import 'package:riasdxd/features/trivia/data/models/actor_ref_model.dart';
import 'package:riasdxd/features/trivia/domain/entities/challenge_entity.dart';

class ChallengeModel extends ChallengeEntity {
  const ChallengeModel({
    required super.code,
    required super.mode,
    required super.deepLink,
    required super.webLink,
    required super.creatorUsername,
    required super.participants,
    super.actor,
    super.expiresAt,
  });

  factory ChallengeModel.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    final participants = rawParticipants is List
        ? rawParticipants
            .whereType<Map>()
            .map((e) => _participant(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <ChallengeParticipantEntity>[];

    final rawActor = json['actorRef'] ?? json['actor'];
    final actor = rawActor is Map
        ? ActorRefModel.fromJson(rawActor.cast<String, dynamic>())
        : null;

    return ChallengeModel(
      code: _str(json['code']),
      mode: _str(json['mode']),
      deepLink: _str(json['deepLink'] ?? json['deeplink']),
      webLink: _str(json['webLink'] ?? json['weblink'] ?? json['url']),
      creatorUsername: _str(
        json['creatorUsername'] ?? json['creatorName'] ?? json['creator'],
      ),
      participants: participants,
      actor: actor,
      expiresAt: _strOrNull(json['expiresAt']),
    );
  }

  static ChallengeParticipantEntity _participant(Map<String, dynamic> m) {
    return ChallengeParticipantEntity(
      userId: _str(m['userId'] ?? m['_id']),
      username: _str(m['username']),
      avatar: _str(m['avatar']),
      score: _int(m['score']),
      completedAt: _str(m['completedAt']),
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static String? _strOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
