import 'package:equatable/equatable.dart';

/// Lightweight reference to the actor/character a fan-test round or challenge
/// is about. Mirrors the server-side `actorRef { id, kind, name, profile }`.
class ActorRefEntity extends Equatable {
  const ActorRefEntity({
    required this.id,
    required this.kind,
    required this.name,
    required this.profileUrl,
  });

  final int id;
  final String kind; // 'person' | 'character'
  final String name;
  final String profileUrl;

  @override
  List<Object?> get props => [id, kind, name, profileUrl];
}
