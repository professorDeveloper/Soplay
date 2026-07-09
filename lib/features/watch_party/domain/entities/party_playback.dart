/// Playback position snapshot for a watch party.
///
/// [receivedAt] is the LOCAL device time at which this snapshot was received —
/// NOT the server clock. All drift math is relative to that local instant so
/// clock skew between server and device can never poison the seek target.
class PartyPlayback {
  final double positionSec;
  final bool isPlaying;
  final double rate;

  /// Local receipt time — the base for drift extrapolation.
  final DateTime receivedAt;

  const PartyPlayback({
    required this.positionSec,
    required this.isPlaying,
    required this.rate,
    required this.receivedAt,
  });

  /// A neutral, paused-at-zero playback. Not `const` because [DateTime] has no
  /// const constructor; kept as a shared immutable instance instead.
  static final PartyPlayback zero = PartyPlayback(
    positionSec: 0,
    isPlaying: false,
    rate: 1,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  factory PartyPlayback.fromJson(Map<String, dynamic> j, {DateTime? receivedAt}) =>
      PartyPlayback(
        positionSec: (j['positionSec'] as num?)?.toDouble() ?? 0,
        isPlaying: j['isPlaying'] as bool? ?? false,
        rate: (j['rate'] as num?)?.toDouble() ?? 1,
        receivedAt: receivedAt ?? DateTime.now(),
      );

  /// Where the player SHOULD be right now, extrapolating from the local
  /// receipt time. NEVER compares serverTime to the device clock.
  double expectedPositionAt(DateTime now) => isPlaying
      ? positionSec + rate * (now.difference(receivedAt).inMilliseconds / 1000.0)
      : positionSec;
}
