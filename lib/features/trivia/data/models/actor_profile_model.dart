import 'package:soplay/features/trivia/domain/entities/actor_profile_entity.dart';

class ActorProfileModel extends ActorProfileEntity {
  const ActorProfileModel({
    required super.id,
    required super.name,
    required super.profileUrl,
    required super.bio,
    required super.birthday,
    required super.birthplace,
    required super.photos,
    required super.filmography,
    required super.imdbId,
    required super.kind,
  });

  factory ActorProfileModel.fromJson(Map<String, dynamic> json) {
    final rawFilmography = json['filmography'] ?? json['credits'];
    final filmography = rawFilmography is List
        ? rawFilmography
            .whereType<Map>()
            .map((e) => _filmographyItem(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <FilmographyItemEntity>[];

    return ActorProfileModel(
      id: _int(json['id'] ?? json['personId'] ?? json['anilistCharId']),
      name: _str(json['name']),
      profileUrl: _str(
        json['profileUrl'] ?? json['profilePath'] ?? json['profile'],
      ),
      bio: _str(json['bio'] ?? json['biography']),
      birthday: _str(json['birthday']),
      birthplace: _str(json['birthplace'] ?? json['placeOfBirth']),
      photos: _strList(json['photos']),
      filmography: filmography,
      imdbId: _str(json['imdbId']),
      kind: _str(json['kind']),
    );
  }

  static FilmographyItemEntity _filmographyItem(Map<String, dynamic> m) {
    return FilmographyItemEntity(
      id: _int(m['id'] ?? m['tmdbId'] ?? m['malId']),
      title: _str(m['title'] ?? m['name']),
      poster: _str(m['poster'] ?? m['posterUrl'] ?? m['poster_path']),
      year: _str(m['year'] ?? m['releaseYear']),
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<String> _strList(dynamic v) {
    if (v is! List) return const <String>[];
    return v
        .map((e) {
          if (e is Map) return _str(e['url'] ?? e['image'] ?? e['file_path']);
          return _str(e);
        })
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}
