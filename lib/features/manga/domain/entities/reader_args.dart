import 'package:soplay/features/detail/domain/entities/episode_entity.dart';

/// Arguments for the manga [ReaderPage]. Chapters reuse [EpisodeEntity] (a
/// chapter is structurally an episode: `episode` number, `label`, `mediaRef`).
class ReaderArgs {
  final String title;
  final String provider;
  final String contentUrl;
  final String? thumbnail;

  /// Ordered chapters (oldest → newest), index 0 = first chapter.
  final List<EpisodeEntity> chapters;
  final int initialChapterIndex;

  /// Page to resume on for the initial chapter (0-based).
  final int resumePage;

  const ReaderArgs({
    required this.title,
    required this.provider,
    required this.contentUrl,
    required this.chapters,
    this.thumbnail,
    this.initialChapterIndex = 0,
    this.resumePage = 0,
  });
}
