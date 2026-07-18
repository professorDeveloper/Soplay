import 'package:equatable/equatable.dart';
import 'actor_ref_entity.dart';

/// A challenge-a-friend game: a shareable [code] + deep/web links, the frozen
/// game [mode]/[actor], and the participants who have played the same 10 clips.
class ChallengeEntity extends Equatable {
  const ChallengeEntity({
    required this.code,
    required this.mode,
    required this.deepLink,
    required this.webLink,
    required this.creatorUsername,
    required this.participants,
    this.actor,
    this.expiresAt,
  });

  final String code;
  final String mode;
  final String deepLink;
  final String webLink;
  final String creatorUsername;
  final List<ChallengeParticipantEntity> participants;
  final ActorRefEntity? actor;
  final String? expiresAt;

  @override
  List<Object?> get props =>
      [code, mode, deepLink, webLink, creatorUsername, participants, actor, expiresAt];
}

/// One participant's result inside a challenge.
class ChallengeParticipantEntity extends Equatable {
  const ChallengeParticipantEntity({
    required this.userId,
    required this.username,
    required this.avatar,
    required this.score,
    required this.completedAt,
  });

  final String userId;
  final String username;
  final String avatar;
  final int score;
  final String completedAt;

  @override
  List<Object?> get props => [userId, username, avatar, score, completedAt];
}
