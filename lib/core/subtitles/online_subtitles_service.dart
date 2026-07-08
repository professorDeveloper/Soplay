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

  final String fileName;

  final String format;
}

class OnlineSubtitlesService {
  OnlineSubtitlesService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

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
    if (data is! List) return const [];
    final out = <OnlineSubtitle>[];
    for (final m in data) {
      if (m is! Map) continue;
      final url = '${m['url'] ?? ''}';
      if (url.isEmpty) continue;
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
