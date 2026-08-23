/// Artwork bundled for the onboarding backdrops and the auth headers.
///
/// Bundled rather than fetched: this is the first frame a new install ever
/// draws, and a network round trip there means an empty screen on exactly the
/// connection most likely to be slow.
///
/// Two sets, because the onboarding tells two different stories — the film
/// catalogue and the anime one — and reusing the same faces for both would make
/// the second slide look like a repeat of the first.
const List<String> kMoviePosters = [
  'assets/onboarding/movie_01.webp',
  'assets/onboarding/movie_02.webp',
  'assets/onboarding/movie_03.webp',
  'assets/onboarding/movie_04.webp',
  'assets/onboarding/movie_05.webp',
  'assets/onboarding/movie_06.webp',
  'assets/onboarding/movie_07.webp',
  'assets/onboarding/movie_08.webp',
  'assets/onboarding/movie_09.webp',
  'assets/onboarding/movie_10.webp',
  'assets/onboarding/movie_11.webp',
  'assets/onboarding/movie_12.webp',
  'assets/onboarding/movie_13.webp',
  'assets/onboarding/movie_14.webp',
  'assets/onboarding/movie_15.webp',
  'assets/onboarding/movie_16.webp',
  'assets/onboarding/movie_17.webp',
  'assets/onboarding/movie_18.webp',
  'assets/onboarding/movie_19.webp',
  'assets/onboarding/movie_20.webp',
  'assets/onboarding/movie_21.webp',
  'assets/onboarding/movie_22.webp',
  'assets/onboarding/movie_23.webp',
  'assets/onboarding/movie_24.webp',
];

/// AniList cover art, which is a different shape and palette from film posters
/// — that difference is what makes the anime slide read as a new subject.
const List<String> kAnimePosters = [
  'assets/onboarding/anime_01.webp',
  'assets/onboarding/anime_02.webp',
  'assets/onboarding/anime_03.webp',
  'assets/onboarding/anime_04.webp',
  'assets/onboarding/anime_05.webp',
  'assets/onboarding/anime_06.webp',
  'assets/onboarding/anime_07.webp',
  'assets/onboarding/anime_08.webp',
  'assets/onboarding/anime_09.webp',
  'assets/onboarding/anime_10.webp',
  'assets/onboarding/anime_11.webp',
  'assets/onboarding/anime_12.webp',
  'assets/onboarding/anime_13.webp',
  'assets/onboarding/anime_14.webp',
  'assets/onboarding/anime_15.webp',
  'assets/onboarding/anime_16.webp',
  'assets/onboarding/anime_17.webp',
  'assets/onboarding/anime_18.webp',
  'assets/onboarding/anime_19.webp',
  'assets/onboarding/anime_20.webp',
  'assets/onboarding/anime_21.webp',
  'assets/onboarding/anime_22.webp',
  'assets/onboarding/anime_23.webp',
  'assets/onboarding/anime_24.webp',
];

/// Both sets woven together, film and anime alternating.
///
/// The third slide is about everything the app holds at once, so its backdrop
/// must not look like either of the two that came before it.
final List<String> kMixedPosters = [
  for (var i = 0; i < kMoviePosters.length; i++) ...[
    kMoviePosters[i],
    kAnimePosters[i % kAnimePosters.length],
  ],
];

/// Live TV channel marks, Uzbek and international.
///
/// Live TV is the one thing in the app that a poster cannot advertise — a
/// channel is recognised by its mark or not at all — so the third slide shows
/// the marks themselves.
const List<String> kChannelLogos = [
  'assets/onboarding/channels/animal_planet.webp',
  'assets/onboarding/channels/bbc_world_news.webp',
  'assets/onboarding/channels/cartoon_network.webp',
  'assets/onboarding/channels/cgtn.webp',
  'assets/onboarding/channels/cna.webp',
  'assets/onboarding/channels/cnn_international.webp',
  'assets/onboarding/channels/dazn.webp',
  'assets/onboarding/channels/discovery_channel.webp',
  'assets/onboarding/channels/disney_channel.webp',
  'assets/onboarding/channels/docubox.webp',
  'assets/onboarding/channels/dreamworks_tv.webp',
  'assets/onboarding/channels/dw_english.webp',
  'assets/onboarding/channels/eleven_sports.webp',
  'assets/onboarding/channels/espn.webp',
  'assets/onboarding/channels/euronews.webp',
  'assets/onboarding/channels/extreme_sports.webp',
  'assets/onboarding/channels/f1_tv.webp',
  'assets/onboarding/channels/fashion_tv.webp',
  'assets/onboarding/channels/filmbox.webp',
  'assets/onboarding/channels/fine_living.webp',
  'assets/onboarding/channels/fox_life.webp',
  'assets/onboarding/channels/france24.webp',
  'assets/onboarding/channels/futbol_tv.webp',
  'assets/onboarding/channels/game_toon.webp',
  'assets/onboarding/channels/investigation_discovery.webp',
  'assets/onboarding/channels/jimjam.webp',
  'assets/onboarding/channels/kbs_world.webp',
  'assets/onboarding/channels/mtv.webp',
  'assets/onboarding/channels/national_geographic.webp',
  'assets/onboarding/channels/nhk_world.webp',
  'assets/onboarding/channels/paramount.webp',
  'assets/onboarding/channels/red_bull_tv.webp',
  'assets/onboarding/channels/rt_documentary.webp',
  'assets/onboarding/channels/star.webp',
  'assets/onboarding/channels/tlc.webp',
  'assets/onboarding/channels/travel_channel.webp',
  'assets/onboarding/channels/tv5monde.webp',
  'assets/onboarding/channels/universal_tv.webp',
  'assets/onboarding/channels/zoo_moo.webp',
];

/// Landscape stills for the television's screen.
///
/// Portrait posters squeezed into a 16:9 panel look like a phone held up to a
/// TV; a still that already fills the frame is what a set actually shows.
const List<String> kScreenStills = [
  'assets/onboarding/screen_01.webp',
  'assets/onboarding/screen_02.webp',
  'assets/onboarding/screen_03.webp',
  'assets/onboarding/screen_04.webp',
  'assets/onboarding/screen_05.webp',
  'assets/onboarding/screen_06.webp',
  'assets/onboarding/screen_07.webp',
  'assets/onboarding/screen_08.webp',
];
