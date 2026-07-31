import 'package:equatable/equatable.dart';

/// One ranked fan of an actor/character (top-fans board + hero preview strip).
class TopFanEntity extends Equatable {
  const TopFanEntity({
    required this.rank,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.bestScore,
    required this.bestFandom,
    required this.updatedAt,
  });

  final int rank;
  final String userId;
  final String username;
  final String avatar;
  final int bestScore;
  final double bestFandom;
  final String updatedAt;

  @override
  List<Object?> get props =>
      [rank, userId, username, avatar, bestScore, bestFandom, updatedAt];
}
