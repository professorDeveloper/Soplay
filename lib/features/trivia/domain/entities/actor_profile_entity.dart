import 'package:equatable/equatable.dart';

/// Full actor / character profile powering the Actor Hero screen.
class ActorProfileEntity extends Equatable {
  const ActorProfileEntity({
    required this.id,
    required this.name,
    required this.profileUrl,
    required this.bio,
    required this.birthday,
    required this.birthplace,
    required this.photos,
    required this.filmography,
    required this.imdbId,
    required this.kind,
  });

  final int id;
  final String name;
  final String profileUrl;
  final String bio;
  final String birthday;
  final String birthplace;
  final List<String> photos;
  final List<FilmographyItemEntity> filmography;
  final String imdbId;
  final String kind; // 'person' | 'character'

  @override
  List<Object?> get props => [
        id,
        name,
        profileUrl,
        bio,
        birthday,
        birthplace,
        photos,
        filmography,
        imdbId,
        kind,
      ];
}

/// A single filmography card in the actor's poster rail.
class FilmographyItemEntity extends Equatable {
  const FilmographyItemEntity({
    required this.id,
    required this.title,
    required this.poster,
    required this.year,
  });

  final int id;
  final String title;
  final String poster;
  final String year;

  @override
  List<Object?> get props => [id, title, poster, year];
}
