import 'party_room.dart';

enum PartyConnection { idle, connecting, connected, reconnecting, error }

enum PartyPhase { none, joining, inRoom, closed }

/// The single source of truth exposed by [WatchPartyService] via a
/// `ValueNotifier<PartyState>`. Immutable; mutate with [copyWith].
class PartyState {
  final PartyConnection connection;
  final PartyPhase phase;
  final PartyRoom? room;
  final String? myUserId;
  final String? errorCode;
  final String? errorMessage;
  final String? closedReason;

  const PartyState({
    required this.connection,
    required this.phase,
    this.room,
    this.myUserId,
    this.errorCode,
    this.errorMessage,
    this.closedReason,
  });

  static const PartyState empty = PartyState(
    connection: PartyConnection.idle,
    phase: PartyPhase.none,
  );

  bool get inParty => phase == PartyPhase.inRoom && room != null;

  bool get isHost =>
      room?.hostUserId != null && room!.hostUserId == myUserId;

  bool get canControl =>
      isHost || (room != null && !room!.onlyHostControls);

  String? get code => room?.code;

  PartyState copyWith({
    PartyConnection? connection,
    PartyPhase? phase,
    PartyRoom? room,
    bool clearRoom = false,
    String? myUserId,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
    String? closedReason,
    bool clearClosedReason = false,
  }) =>
      PartyState(
        connection: connection ?? this.connection,
        phase: phase ?? this.phase,
        room: clearRoom ? null : (room ?? this.room),
        myUserId: myUserId ?? this.myUserId,
        errorCode: clearError ? null : (errorCode ?? this.errorCode),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        closedReason:
            clearClosedReason ? null : (closedReason ?? this.closedReason),
      );
}
