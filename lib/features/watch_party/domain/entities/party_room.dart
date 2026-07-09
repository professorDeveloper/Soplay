import 'party_content.dart';
import 'party_member.dart';
import 'party_playback.dart';

/// The full state of a watch party room, built from a `party:state` snapshot
/// or a REST create/preview response.
class PartyRoom {
  final String code;
  final String? hostUserId;
  final bool onlyHostControls;
  final int maxMembers;
  final List<PartyMember> members;
  final PartyContent? content;
  final PartyPlayback playback;

  const PartyRoom({
    required this.code,
    this.hostUserId,
    this.onlyHostControls = true,
    this.maxMembers = 2,
    this.members = const <PartyMember>[],
    this.content,
    required this.playback,
  });

  int get onlineCount => members.where((m) => m.online).length;

  static bool _onlyHostControls(dynamic settings) {
    if (settings is Map) {
      return settings['onlyHostControls'] as bool? ?? true;
    }
    return true;
  }

  static PartyContent? _content(dynamic raw) =>
      raw is Map ? PartyContent.fromJson(Map<String, dynamic>.from(raw)) : null;

  static PartyPlayback _playback(dynamic raw) => raw is Map
      ? PartyPlayback.fromJson(
          Map<String, dynamic>.from(raw),
          receivedAt: DateTime.now(),
        )
      : PartyPlayback.zero;

  /// From a `party:state` socket snapshot.
  factory PartyRoom.fromSnapshot(Map<String, dynamic> j) => PartyRoom(
        code: j['code'] as String? ?? '',
        hostUserId: j['hostUserId'] as String?,
        onlyHostControls: _onlyHostControls(j['settings']),
        maxMembers: (j['maxMembers'] as num?)?.toInt() ?? 2,
        members: PartyMember.listFrom(j['members']),
        content: _content(j['content']),
        playback: _playback(j['playback']),
      );

  /// From a REST body — `POST /watch-party` returns `{code, party}` (pass the
  /// `party` object here) and `GET /watch-party/:code` returns a flat object.
  factory PartyRoom.fromRest(Map<String, dynamic> j) {
    final rawHost = j['host'];
    final host = rawHost is Map ? Map<String, dynamic>.from(rawHost) : null;
    return PartyRoom(
      code: j['code'] as String? ?? '',
      hostUserId: (j['hostUserId'] as String?) ?? host?['userId'] as String?,
      onlyHostControls: _onlyHostControls(j['settings']),
      maxMembers: (j['maxMembers'] as num?)?.toInt() ?? 2,
      members: PartyMember.listFrom(j['members']),
      content: _content(j['content']),
      playback: _playback(j['playback']),
    );
  }

  PartyRoom copyWith({
    String? code,
    String? hostUserId,
    bool? onlyHostControls,
    int? maxMembers,
    List<PartyMember>? members,
    PartyContent? content,
    PartyPlayback? playback,
  }) =>
      PartyRoom(
        code: code ?? this.code,
        hostUserId: hostUserId ?? this.hostUserId,
        onlyHostControls: onlyHostControls ?? this.onlyHostControls,
        maxMembers: maxMembers ?? this.maxMembers,
        members: members ?? this.members,
        content: content ?? this.content,
        playback: playback ?? this.playback,
      );
}
