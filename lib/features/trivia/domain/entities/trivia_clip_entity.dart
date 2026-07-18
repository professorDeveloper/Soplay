import 'package:equatable/equatable.dart';
import 'trivia_option_entity.dart';

/// A single trivia clip as delivered to the client: the video to play, its
/// duration, and the shuffled answer options. Carries NO correct answer —
/// `videoUrl`, `durationMs` and `options` only.
class TriviaClipEntity extends Equatable {
  const TriviaClipEntity({
    required this.clipId,
    required this.videoUrl,
    required this.durationMs,
    required this.options,
  });

  final String clipId;
  final String videoUrl;
  final int durationMs;
  final List<TriviaOptionEntity> options;

  @override
  List<Object?> get props => [clipId, videoUrl, durationMs, options];
}
