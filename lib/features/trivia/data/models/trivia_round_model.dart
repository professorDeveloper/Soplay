import 'package:soplay/features/trivia/data/models/actor_ref_model.dart';
import 'package:soplay/features/trivia/data/models/trivia_clip_model.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_round_entity.dart';

class TriviaRoundModel extends TriviaRoundEntity {
  const TriviaRoundModel({
    required super.roundId,
    required super.mode,
    required super.clips,
    required super.index,
    super.actor,
    super.challengeCode,
  });

  factory TriviaRoundModel.fromJson(Map<String, dynamic> json) {
    final rawClips = json['clips'];
    final clips = rawClips is List
        ? rawClips
            .whereType<Map>()
            .map((e) => TriviaClipModel.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <TriviaClipModel>[];

    final rawActor = json['actorRef'] ?? json['actor'];
    final actor = rawActor is Map
        ? ActorRefModel.fromJson(rawActor.cast<String, dynamic>())
        : null;

    return TriviaRoundModel(
      roundId: _str(json['roundId'] ?? json['_id'] ?? json['id']),
      mode: _str(json['mode']),
      clips: clips,
      index: _int(json['index'] ?? json['currentIndex']),
      actor: actor,
      challengeCode: _strOrNull(json['challengeCode'] ?? json['code']),
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
