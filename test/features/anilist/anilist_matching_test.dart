import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// The pure decisions behind AniList tracking.
///
/// These are worth testing precisely because the consequences are invisible:
/// a bad normalization silently attaches the wrong show, and a wrong
/// `nextEpisode` offers to mark an episode watched that has not aired. Neither
/// produces an error — they produce a quietly wrong list.
void main() {
  group('normalizeTitle', () {
    test('ignores case and punctuation', () {
      expect(
        AnilistTracker.normalizeTitle('Fate/stay night: Unlimited Blade Works'),
        AnilistTracker.normalizeTitle('fate stay night unlimited blade works'),
      );
    });

    test('strips the release tags source sites append', () {
      expect(
        AnilistTracker.normalizeTitle('Naruto Shippuden [1080p] (Uzbek tarjima)'),
        AnilistTracker.normalizeTitle('Naruto Shippuden'),
      );
    });

    test('keeps non-Latin scripts intact', () {
      // A Latin-only filter would reduce both of these to empty strings and
      // then declare them equal — the worst possible failure for a matcher.
      expect(AnilistTracker.normalizeTitle('鋼の錬金術師'), isNotEmpty);
      expect(
        AnilistTracker.normalizeTitle('鋼の錬金術師') ==
            AnilistTracker.normalizeTitle('進撃の巨人'),
        isFalse,
      );
    });

    test('collapses whitespace rather than leaving gaps behind', () {
      expect(AnilistTracker.normalizeTitle('  One   Piece  '), 'one piece');
    });

    test('different shows do not collapse into one another', () {
      expect(
        AnilistTracker.normalizeTitle('Attack on Titan') ==
            AnilistTracker.normalizeTitle('Attack on Titan Season 2'),
        isFalse,
      );
    });
  });

  group('AnilistLinkStore.keyFor', () {
    test('is case-insensitive so one title is not linked twice', () {
      expect(
        AnilistLinkStore.keyFor('CloudStream', 'HTTPS://X.COM/A'),
        AnilistLinkStore.keyFor('cloudstream', 'https://x.com/a'),
      );
    });

    test('separates the same url on different providers', () {
      // Episode numbering routinely differs between sources, so these must not
      // share one link.
      expect(
        AnilistLinkStore.keyFor('a', 'https://x.com/1') ==
            AnilistLinkStore.keyFor('b', 'https://x.com/1'),
        isFalse,
      );
    });
  });

  group('AnilistListEntry', () {
    AnilistListEntry entry({
      required int progress,
      int? episodes,
      AnilistAiring? airing,
    }) =>
        AnilistListEntry(
          id: 1,
          media: AnilistMedia(id: 1, episodes: episodes, nextAiring: airing),
          status: AnilistStatus.current.value,
          progress: progress,
        );

    test('offers the next episode while there are unwatched ones', () {
      expect(entry(progress: 3, episodes: 12).nextEpisode, 4);
    });

    test('offers nothing once the series is finished', () {
      expect(entry(progress: 12, episodes: 12).nextEpisode, isNull);
    });

    test('caps at what has aired, not at the announced total', () {
      // 24 announced, episode 6 airs next → 5 exist. A viewer on 5 is caught
      // up, and "+1" would report an episode nobody has seen.
      final e = entry(
        progress: 5,
        episodes: 24,
        airing: const AnilistAiring(episode: 6, airingAt: 4102444800),
      );
      expect(e.nextEpisode, isNull);
      expect(e.behindBy, 0);
    });

    test('counts how far behind the viewer is on an airing show', () {
      final e = entry(
        progress: 2,
        episodes: 24,
        airing: const AnilistAiring(episode: 6, airingAt: 4102444800),
      );
      expect(e.behindBy, 3);
      expect(e.nextEpisode, 3);
    });

    test('completion is null when the total is unknown', () {
      expect(entry(progress: 4).completion, isNull);
      expect(entry(progress: 6, episodes: 12).completion, 0.5);
    });
  });

  group('AnilistAiring', () {
    test('reads AniList seconds, not milliseconds', () {
      const airing = AnilistAiring(episode: 1, airingAt: 1700000000);
      expect(
        airing.airsAt.millisecondsSinceEpoch,
        1700000000 * 1000,
      );
    });

    test('knows an episode in the past has aired', () {
      const past = AnilistAiring(episode: 1, airingAt: 1000000000);
      expect(past.hasAired, isTrue);
    });
  });

  group('AnilistMedia', () {
    test('searchTitles drops blanks and duplicates, best guess first', () {
      const media = AnilistMedia(
        id: 1,
        englishTitle: 'Bleach',
        romajiTitle: 'Bleach',
        nativeTitle: 'ブリーチ',
      );
      expect(media.searchTitles, ['Bleach', 'ブリーチ']);
    });

    test('displayTitle falls back when English is missing', () {
      const media = AnilistMedia(id: 1, romajiTitle: 'Shingeki no Kyojin');
      expect(media.displayTitle, 'Shingeki no Kyojin');
    });
  });
}
