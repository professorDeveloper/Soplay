/// An emoji reaction broadcast in a watch party. Server payload nests the
/// author under `user: {id, username, photoURL}`.
class PartyReaction {
  final String userId;
  final String? username;
  final String? photoURL;
  final String emoji;
  final int ts;

  const PartyReaction({
    required this.userId,
    this.username,
    this.photoURL,
    required this.emoji,
    required this.ts,
  });

  factory PartyReaction.fromJson(Map<String, dynamic> j) {
    final rawUser = j['user'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : const <String, dynamic>{};
    return PartyReaction(
      userId: user['id'] as String? ?? '',
      username: user['username'] as String?,
      photoURL: user['photoURL'] as String?,
      emoji: j['emoji'] as String? ?? '',
      ts: (j['ts'] as num?)?.toInt() ?? 0,
    );
  }
}
