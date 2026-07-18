import 'package:equatable/equatable.dart';
import 'top_fan_entity.dart';

/// Denormalized fan aggregate for an actor/character: rounds played, average
/// fandom, and the ranked list of [topFans].
class ActorFanStatEntity extends Equatable {
  const ActorFanStatEntity({
    required this.actorId,
    required this.kind,
    required this.name,
    required this.profileUrl,
    required this.roundsPlayed,
    required this.avgFandom,
    required this.topFans,
  });

  final int actorId;
  final String kind; // 'person' | 'character'
  final String name;
  final String profileUrl;
  final int roundsPlayed;
  final double avgFandom;
  final List<TopFanEntity> topFans;

  @override
  List<Object?> get props =>
      [actorId, kind, name, profileUrl, roundsPlayed, avgFandom, topFans];
}
