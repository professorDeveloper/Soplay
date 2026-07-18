import 'package:equatable/equatable.dart';

/// A single answer choice for a clip. Carries an opaque [optionId] plus the
/// candidate title/poster — but NO flag revealing whether it is the correct
/// answer (anti-cheat: correctness never leaves the server pre-submit).
class TriviaOptionEntity extends Equatable {
  const TriviaOptionEntity({
    required this.optionId,
    required this.title,
    required this.poster,
  });

  final String optionId;
  final String title;
  final String poster;

  @override
  List<Object?> get props => [optionId, title, poster];
}
