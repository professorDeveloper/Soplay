/// A chat line broadcast in a watch party. Server payload nests the author
/// under `user: {id, username, photoURL}`.
class PartyChatMessage {
  final String userId;
  final String? username;
  final String? photoURL;
  final String text;
  final int ts;

  const PartyChatMessage({
    required this.userId,
    this.username,
    this.photoURL,
    required this.text,
    required this.ts,
  });

  factory PartyChatMessage.fromJson(Map<String, dynamic> j) {
    final rawUser = j['user'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : const <String, dynamic>{};
    return PartyChatMessage(
      userId: user['id'] as String? ?? '',
      username: user['username'] as String?,
      photoURL: user['photoURL'] as String?,
      text: j['text'] as String? ?? '',
      ts: (j['ts'] as num?)?.toInt() ?? 0,
    );
  }
}
