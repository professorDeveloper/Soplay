import 'package:equatable/equatable.dart';

/// A cast-search / popular-grid card. Unifies TMDB people and AniList
/// characters via [kind]; [id] is the provider-native id.
class CastPersonEntity extends Equatable {
  const CastPersonEntity({
    required this.id,
    required this.name,
    required this.profileUrl,
    required this.knownFor,
    required this.kind,
  });

  final int id;
  final String name;
  final String profileUrl;
  final List<String> knownFor;
  final String kind; // 'person' | 'character'

  @override
  List<Object?> get props => [id, name, profileUrl, knownFor, kind];
}
