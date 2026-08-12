import 'package:riasdxd/features/trivia/domain/entities/trivia_option_entity.dart';

class TriviaOptionModel extends TriviaOptionEntity {
  const TriviaOptionModel({
    required super.optionId,
    required super.title,
    required super.poster,
  });

  factory TriviaOptionModel.fromJson(Map<String, dynamic> json) {
    return TriviaOptionModel(
      optionId: _str(json['optionId'] ?? json['id']),
      title: _str(json['title']),
      poster: _str(json['poster'] ?? json['posterUrl'] ?? json['poster_path']),
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();
}
