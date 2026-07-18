import 'package:soplay/features/trivia/data/models/trivia_option_model.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_clip_entity.dart';

class TriviaClipModel extends TriviaClipEntity {
  const TriviaClipModel({
    required super.clipId,
    required super.videoUrl,
    required super.durationMs,
    required super.options,
  });

  factory TriviaClipModel.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = rawOptions is List
        ? rawOptions
            .whereType<Map>()
            .map((e) => TriviaOptionModel.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <TriviaOptionModel>[];

    return TriviaClipModel(
      clipId: _str(json['clipId'] ?? json['_id'] ?? json['id']),
      videoUrl: _str(json['videoUrl'] ?? json['url']),
      durationMs: _int(json['durationMs'] ?? json['duration']),
      options: options,
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
