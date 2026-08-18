import 'package:dio/dio.dart';
import 'package:soplay/features/anilist/data/anilist_constants.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// Thin GraphQL transport for AniList.
///
/// Deliberately on its OWN Dio, not the app's: the app's client carries a Sozo
/// bearer token and a stack of interceptors (auth refresh, Cloudflare bypass)
/// that have no business firing at anilist.co — and sending our token to a third
/// party would be worse than pointless.
class AnilistApi {
  AnilistApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          );

  final Dio _dio;

  /// The media selection every query shares.
  ///
  /// One constant rather than a copy per query: the entity parses these fields
  /// unconditionally, so a field added to search but forgotten in the library
  /// query shows up as a silently missing value rather than an error.
  static const String _mediaFields = '''
    id
    episodes
    averageScore
    seasonYear
    format
    status
    siteUrl
    title { romaji english native }
    coverImage { large }
    bannerImage
    description(asHtml: false)
    isAdult
    nextAiringEpisode { episode airingAt }
  ''';

  /// Runs [query]. [token] is optional: search and media lookups are public,
  /// only the viewer's own list and any write need it.
  Future<Map<String, dynamic>> _run(
    String query, {
    Map<String, dynamic> variables = const {},
    String? token,
  }) async {
    final response = await _dio.post(
      AnilistConstants.graphqlEndpoint,
      data: {'query': query, 'variables': variables},
      options: Options(
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ),
    );

    final body = response.data;
    if (body is! Map) throw const AnilistException('Unexpected AniList reply');

    // GraphQL reports failures in a 200 body, so a non-throwing Dio call is not
    // the same as a successful query.
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map ? first['message']?.toString() : null;
      throw AnilistException(message ?? 'AniList rejected the request');
    }

    final data = body['data'];
    if (data is! Map) throw const AnilistException('AniList returned no data');
    return data.cast<String, dynamic>();
  }

  /// Who the stored token belongs to. Also the cheapest way to tell whether a
  /// token is still valid — AniList tokens last about a year but can be revoked.
  Future<AnilistViewer> viewer(String token) async {
    const query = '''
      query {
        Viewer {
          id
          name
          avatar { large }
          siteUrl
        }
      }
    ''';
    final data = await _run(query, token: token);
    final v = data['Viewer'];
    if (v is! Map) throw const AnilistException('Not signed in to AniList');
    return AnilistViewer.fromJson(v.cast<String, dynamic>());
  }

  /// The viewer's anime list, every status in one call.
  ///
  /// AniList returns it grouped by status; flattening here keeps the grouping
  /// decision in the UI rather than baking one layout into the transport.
  Future<List<AnilistListEntry>> mediaList({
    required String token,
    required int userId,
  }) async {
    final query = '''
      query (\$userId: Int) {
        MediaListCollection(userId: \$userId, type: ANIME) {
          lists {
            entries {
              id
              status
              progress
              score(format: POINT_10)
              updatedAt
              media { $_mediaFields }
            }
          }
        }
      }
    ''';
    final data = await _run(query, variables: {'userId': userId}, token: token);

    final collection = data['MediaListCollection'];
    final lists = collection is Map ? collection['lists'] : null;
    if (lists is! List) return const [];

    // Custom lists make AniList repeat one entry under several list objects.
    // De-duped by entry id so a title on a custom list is not counted twice.
    final seen = <int>{};
    final out = <AnilistListEntry>[];
    for (final list in lists.whereType<Map>()) {
      final entries = list['entries'];
      if (entries is! List) continue;
      for (final raw in entries.whereType<Map>()) {
        final entry = AnilistListEntry.fromJson(raw.cast<String, dynamic>());
        if (seen.add(entry.id)) out.add(entry);
      }
    }
    return out;
  }

  /// Public title search — used to attach an AniList id to something the user
  /// is watching from a source that knows nothing about AniList.
  Future<List<AnilistMedia>> searchMedia(String query, {int perPage = 20}) async {
    if (query.trim().isEmpty) return const [];
    final gql = '''
      query (\$search: String, \$perPage: Int) {
        Page(page: 1, perPage: \$perPage) {
          media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
            $_mediaFields
          }
        }
      }
    ''';
    final data = await _run(
      gql,
      variables: {'search': query.trim(), 'perPage': perPage},
    );
    final page = data['Page'];
    final media = page is Map ? page['media'] : null;
    if (media is! List) return const [];
    return media
        .whereType<Map>()
        .map((e) => AnilistMedia.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Everything airing between [from] and [to].
  ///
  /// Paged rather than a single large request: a day of global airings runs to
  /// a few dozen entries and AniList caps perPage at 50, so asking for one page
  /// silently truncates the evening. The cap on pages is a safety net against a
  /// window someone widens later, not a real limit — a day never reaches it.
  Future<List<AnilistScheduledAiring>> airingSchedule({
    required DateTime from,
    required DateTime to,
    bool includeAdult = false,
  }) async {
    final gql = '''
      query (\$start: Int, \$end: Int, \$page: Int) {
        Page(page: \$page, perPage: 50) {
          pageInfo { hasNextPage }
          airingSchedules(
            airingAt_greater: \$start
            airingAt_lesser: \$end
            sort: TIME
          ) {
            episode
            airingAt
            media { $_mediaFields }
          }
        }
      }
    ''';

    final start = from.toUtc().millisecondsSinceEpoch ~/ 1000;
    final end = to.toUtc().millisecondsSinceEpoch ~/ 1000;
    final out = <AnilistScheduledAiring>[];

    for (var page = 1; page <= 10; page++) {
      final data = await _run(
        gql,
        variables: {'start': start, 'end': end, 'page': page},
      );
      final pageData = data['Page'];
      if (pageData is! Map) break;

      final schedules = pageData['airingSchedules'];
      if (schedules is List) {
        for (final raw in schedules.whereType<Map>()) {
          final airing =
              AnilistScheduledAiring.fromJson(raw.cast<String, dynamic>());
          if (airing == null) continue;
          if (!includeAdult && airing.media.isAdult) continue;
          out.add(airing);
        }
      }

      final info = pageData['pageInfo'];
      final hasNext = info is Map && info['hasNextPage'] == true;
      if (!hasNext) break;
    }
    return out;
  }

  /// The viewer's own entry for one title, or null if it is not on their list.
  ///
  /// Read before every automatic write so progress is never moved BACKWARDS:
  /// a rewatch, a second device, or a partly-watched episode would otherwise
  /// overwrite a higher number the account already holds.
  Future<AnilistEntryState?> entryState({
    required String token,
    required int mediaId,
  }) async {
    const query = '''
      query (\$mediaId: Int) {
        Media(id: \$mediaId, type: ANIME) {
          episodes
          mediaListEntry { progress status }
        }
      }
    ''';
    final data = await _run(query, variables: {'mediaId': mediaId}, token: token);
    final media = data['Media'];
    if (media is! Map) return null;
    final entry = media['mediaListEntry'];
    return AnilistEntryState(
      onList: entry is Map,
      progress: entry is Map ? (entry['progress'] as num?)?.toInt() ?? 0 : 0,
      status: entry is Map ? entry['status'] as String? : null,
      totalEpisodes: (media['episodes'] as num?)?.toInt(),
    );
  }

  /// Writes progress back to AniList.
  ///
  /// [progress] is an episode COUNT, not an index — AniList means "episodes
  /// finished", so passing a zero-based index silently reports one episode less
  /// than the viewer actually watched.
  ///
  /// Returns what AniList stored, which is not always what was sent: it clamps
  /// progress to the episode total and flips status to COMPLETED on the last
  /// episode. Echoing the server's answer keeps the UI from showing a number
  /// the account does not actually hold.
  Future<AnilistSaveResult> saveProgress({
    required String token,
    required int mediaId,
    required int progress,
    String? status,
  }) async {
    const mutation = '''
      mutation (\$mediaId: Int, \$progress: Int, \$status: MediaListStatus) {
        SaveMediaListEntry(mediaId: \$mediaId, progress: \$progress, status: \$status) {
          id
          progress
          status
        }
      }
    ''';
    final data = await _run(
      mutation,
      variables: {
        'mediaId': mediaId,
        'progress': progress,
        'status': ?status,
      },
      token: token,
    );
    final saved = data['SaveMediaListEntry'];
    if (saved is! Map) throw const AnilistException('AniList saqlamadi');
    return AnilistSaveResult(
      progress: (saved['progress'] as num?)?.toInt() ?? progress,
      status: saved['status'] as String? ?? status ?? AnilistStatus.current.value,
    );
  }
}

/// What AniList actually stored after a write.
class AnilistSaveResult {
  const AnilistSaveResult({required this.progress, required this.status});
  final int progress;
  final String status;
}

/// The viewer's current position on one title, as AniList holds it.
class AnilistEntryState {
  const AnilistEntryState({
    required this.onList,
    required this.progress,
    this.status,
    this.totalEpisodes,
  });

  final bool onList;
  final int progress;
  final String? status;
  final int? totalEpisodes;
}

class AnilistException implements Exception {
  const AnilistException(this.message);
  final String message;
  @override
  String toString() => message;
}
