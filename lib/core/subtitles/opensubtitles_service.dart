import 'package:dio/dio.dart';

class OpenSubtitle {
  const OpenSubtitle({
    required this.fileId,
    required this.language,
    required this.release,
    required this.downloadCount,
  });

  final int fileId;
  final String language;
  final String release;
  final int downloadCount;
}

/// Thin client for the OpenSubtitles REST API (api.opensubtitles.com/api/v1).
/// Title-based search → pick → resolve a temporary download link for the .srt.
/// The API key is the user's own (opensubtitles.com ▸ API Consumers).
class OpenSubtitlesService {
  OpenSubtitlesService._();

  static const String _base = 'https://api.opensubtitles.com/api/v1';

  static Dio _client(String apiKey) => Dio(
        BaseOptions(
          headers: {
            'Api-Key': apiKey,
            'User-Agent': 'Sozo v1.0',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );

  static Future<List<OpenSubtitle>> search({
    required String apiKey,
    required String query,
    String languages = 'en',
    int? season,
    int? episode,
  }) async {
    final params = <String, dynamic>{
      'query': query,
      'languages': languages,
    };
    if (season != null) params['season_number'] = season;
    if (episode != null) params['episode_number'] = episode;

    final res = await _client(apiKey).get('$_base/subtitles',
        queryParameters: params);
    if (res.statusCode != 200) {
      throw Exception(_msg(res));
    }
    final data = (res.data is Map ? res.data['data'] : null) as List? ?? const [];
    final out = <OpenSubtitle>[];
    for (final e in data) {
      if (e is! Map) continue;
      final attr = (e['attributes'] as Map?) ?? const {};
      final files = (attr['files'] as List?) ?? const [];
      if (files.isEmpty) continue;
      final fileId = (files.first as Map?)?['file_id'];
      final id = fileId is num ? fileId.toInt() : int.tryParse('$fileId');
      if (id == null) continue;
      final feature = (attr['feature_details'] as Map?) ?? const {};
      out.add(OpenSubtitle(
        fileId: id,
        language: '${attr['language'] ?? ''}'.toUpperCase(),
        release: '${attr['release'] ?? feature['title'] ?? query}',
        downloadCount: (attr['download_count'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  static Future<String?> downloadLink({
    required String apiKey,
    required int fileId,
  }) async {
    final res = await _client(apiKey).post('$_base/download',
        data: {'file_id': fileId});
    if (res.statusCode != 200) {
      throw Exception(_msg(res));
    }
    return (res.data is Map ? res.data['link'] : null) as String?;
  }

  static String _msg(Response res) {
    final d = res.data;
    final m = (d is Map ? (d['message'] ?? d['error']) : null)?.toString();
    return m ?? 'OpenSubtitles error ${res.statusCode}';
  }
}
