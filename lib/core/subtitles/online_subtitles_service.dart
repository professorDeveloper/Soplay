import 'package:dio/dio.dart';

class OnlineSubtitle {
  const OnlineSubtitle({
    required this.url,
    required this.language,
    required this.display,
    required this.downloadCount,
    required this.hearingImpaired,
    this.fileName = '',
    this.format = '',
  });

  final String url;
  final String language;
  final String display;
  final int downloadCount;
  final bool hearingImpaired;

  /// The provider's exact release / file name for this subtitle when present
  /// (e.g. "Movie.2010.1080p.BluRay.x264-GROUP"), so the user can match it to
  /// their video. Empty when the provider only exposes a language label.
  final String fileName;

  /// Subtitle format (SRT / VTT / ASS …) when reported.
  final String format;
}

/// Online subtitle search. Resolves the title to an IMDB id via Cinemeta
/// (Stremio metadata, keyless), then queries Wyzie Subs for direct .srt links.
class OnlineSubtitlesService {
  OnlineSubtitlesService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  /// Title → IMDB id (e.g. "tt1375666"). Tries the movie or series catalog.
  static Future<String?> resolveImdbId({
    required String title,
    required bool series,
  }) async {
    final cat = series ? 'series' : 'movie';
    final q = Uri.encodeComponent(title);
    try {
      final res = await _dio.get(
        'https://v3-cinemeta.strem.io/catalog/$cat/top/search=$q.json',
      );
      final metas = (res.data is Map ? res.data['metas'] : null) as List? ??
          const [];
      for (final m in metas) {
        final id = (m is Map ? m['id'] : null)?.toString();
        if (id != null && id.startsWith('tt')) return id;
      }
    } catch (_) {}
    return null;
  }

  static Future<List<OnlineSubtitle>> search({
    required String wyzieKey,
    required String title,
    bool isSerial = false,
    int? season,
    int? episode,
  }) async {
    final imdb = await resolveImdbId(title: title, series: isSerial);
    if (imdb == null) return const [];

    var results = await _wyzie(wyzieKey, imdb,
        season: isSerial ? (season ?? 1) : null,
        episode: isSerial ? episode : null);
    // Series episode filter sometimes returns nothing — fall back to the whole
    // title so the user still gets options to pick from.
    if (results.isEmpty && isSerial) {
      results = await _wyzie(wyzieKey, imdb);
    }
    return results;
  }

  static Future<List<OnlineSubtitle>> _wyzie(
    String key,
    String imdbId, {
    int? season,
    int? episode,
  }) async {
    final params = <String, dynamic>{'key': key, 'id': imdbId};
    if (season != null) params['season'] = season;
    if (episode != null) params['episode'] = episode;
    final res = await _dio.get('https://sub.wyzie.io/search',
        queryParameters: params);
    final data = res.data;
    if (data is! List) return const []; // 400 body = no subtitles found
    final out = <OnlineSubtitle>[];
    for (final m in data) {
      if (m is! Map) continue;
      final url = '${m['url'] ?? ''}';
      if (url.isEmpty) continue;
      // Providers name the exact release differently; take the most specific
      // field available so the user sees the real subtitle name when it exists.
      final fileName =
          '${m['media'] ?? m['fileName'] ?? m['release'] ?? m['source'] ?? m['title'] ?? ''}'
              .trim();
      out.add(OnlineSubtitle(
        url: url,
        language: '${m['language'] ?? ''}'.toUpperCase(),
        display: '${m['display'] ?? m['language'] ?? 'Subtitle'}',
        downloadCount: (m['downloadCount'] as num?)?.toInt() ?? 0,
        hearingImpaired: m['isHearingImpaired'] == true,
        fileName: fileName,
        format: '${m['format'] ?? ''}'.toUpperCase(),
      ));
    }
    out.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
    return out;
  }
}
