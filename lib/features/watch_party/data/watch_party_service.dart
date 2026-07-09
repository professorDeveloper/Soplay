import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/network/token_refresher.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/watch_party/data/watch_party_remote_data_source.dart';
import 'package:soplay/features/watch_party/data/watch_party_socket_client.dart';
import 'package:soplay/features/watch_party/domain/entities/party_chat_message.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/domain/entities/party_member.dart';
import 'package:soplay/features/watch_party/domain/entities/party_playback.dart';
import 'package:soplay/features/watch_party/domain/entities/party_reaction.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';
import 'package:soplay/features/watch_party/domain/entities/party_state.dart';

/// Live watch-party session. Registered as an eager get_it singleton and is the
/// single source of truth via [state]. Mirrors `StreakService`'s shape
/// (ValueNotifier + broadcast streams) but drives a socket instead of REST.
class WatchPartyService with WidgetsBindingObserver {
  WatchPartyService({
    required this.remote,
    required this.hive,
    required this.tokenRefresher,
    WatchPartySocketClient? socket,
  }) : _socket = socket ?? WatchPartySocketClient() {
    WidgetsBinding.instance.addObserver(this);
    _wireSocket();
  }

  final WatchPartyRemoteDataSource remote;
  final HiveService hive;
  final TokenRefresher tokenRefresher;
  final WatchPartySocketClient _socket;

  final ValueNotifier<PartyState> state =
      ValueNotifier<PartyState>(PartyState.empty);

  final StreamController<PartyChatMessage> _chatCtrl =
      StreamController<PartyChatMessage>.broadcast();
  final StreamController<PartyReaction> _reactionCtrl =
      StreamController<PartyReaction>.broadcast();
  final StreamController<PartyContent> _contentCtrl =
      StreamController<PartyContent>.broadcast();
  final StreamController<PartyPlayback> _syncCtrl =
      StreamController<PartyPlayback>.broadcast();
  final StreamController<String> _errorCtrl =
      StreamController<String>.broadcast();

  Stream<PartyChatMessage> get chat => _chatCtrl.stream;
  Stream<PartyReaction> get reactions => _reactionCtrl.stream;
  Stream<PartyContent> get contentChanges => _contentCtrl.stream;
  Stream<PartyPlayback> get syncs => _syncCtrl.stream;
  Stream<String> get errors => _errorCtrl.stream;

  String? _currentCode;
  bool _handshakeRetried = false;
  bool _disposed = false;

  // Own-echo dedupe: each outgoing chat/reaction carries a per-send client id
  // that the server echoes back. An incoming event is suppressed only when its
  // client id matches a still-pending send from THIS device — never by userId,
  // which is shared with a second device signed into the same account.
  int _clientSeq = 0;
  final Set<String> _pendingChatIds = <String>{};
  final Set<String> _pendingReactionIds = <String>{};

  bool get connected => _socket.connected;

  String? get _myUserId {
    final id = hive.getUser()?.id;
    return (id == null || id.isEmpty) ? null : id;
  }

  String get _origin => Uri.parse(AppConstants.baseUrl).origin;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// REST create → connect → join (join emitted on the `connect` event).
  Future<PartyRoom> createParty({PartyContent? content}) async {
    // New session gets a fresh one-shot handshake recovery.
    _handshakeRetried = false;
    final body = await remote.createParty(content: content);
    final rawParty = body['party'];
    final partyJson =
        rawParty is Map ? Map<String, dynamic>.from(rawParty) : body;
    final room = PartyRoom.fromRest(partyJson);
    _currentCode = room.code;
    state.value = state.value.copyWith(
      room: room,
      phase: PartyPhase.joining,
      myUserId: _myUserId,
      clearError: true,
      clearClosedReason: true,
    );
    await _openSocket();
    return room;
  }

  /// REST-only room preview for a join screen.
  Future<PartyRoom> preview(String code) async {
    final body = await remote.preview(code);
    return PartyRoom.fromRest(body);
  }

  /// Connect → emit `party:join`.
  Future<void> joinParty(String code) async {
    // New session gets a fresh one-shot handshake recovery.
    _handshakeRetried = false;
    _currentCode = code;
    state.value = state.value.copyWith(
      phase: PartyPhase.joining,
      myUserId: _myUserId,
      clearError: true,
      clearClosedReason: true,
    );
    await _openSocket();
  }

  /// Emit `party:leave` → disconnect → reset to empty.
  Future<void> leaveParty() async {
    final code = _currentCode;
    if (code != null) {
      _socket.emit('party:leave', <String, dynamic>{'code': code});
    }
    _currentCode = null;
    _socket.disconnect();
    state.value = PartyState.empty;
  }

  /// Host-only: REST DELETE. The server broadcasts `party:closed`.
  Future<void> closeParty() async {
    final code = _currentCode ?? state.value.code;
    if (code == null) return;
    try {
      await remote.close(code);
    } catch (_) {
      // The party:closed broadcast (if the room really went away) still cleans
      // up; a failed delete simply leaves the caller's UI as-is.
      rethrow;
    } finally {
      _currentCode = null;
      _socket.disconnect();
      state.value = PartyState.empty;
    }
  }

  Future<void> invite(String userId) async {
    final code = _currentCode ?? state.value.code;
    if (code == null) return;
    await remote.invite(code, userId);
  }

  void sendControl({required String action, double? positionSec, double? rate}) {
    if (!_canEmit) return;
    _socket.emit('party:control', <String, dynamic>{
      'code': _currentCode,
      'action': action,
      'positionSec': ?positionSec,
      'rate': ?rate,
    });
  }

  void sendContent(PartyContent content) {
    if (!_canEmit) return;
    _socket.emit('party:content', <String, dynamic>{
      'code': _currentCode,
      ...content.toJson(),
    });
  }

  void sendHeartbeat(double positionSec) {
    if (!_canEmit) return;
    _socket.emit('party:heartbeat', <String, dynamic>{
      'code': _currentCode,
      'positionSec': positionSec,
    });
  }

  void sendChat(String text) {
    if (!_canEmit) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final capped =
        trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
    final clientId = _nextClientId();
    _rememberPending(_pendingChatIds, clientId);
    _socket.emit('party:chat', <String, dynamic>{
      'code': _currentCode,
      'text': capped,
      'clientId': clientId,
    });
    // Optimistic local echo: show instantly instead of waiting for the server
    // round-trip (which can be slow on a distant server). The server echoes our
    // clientId back; _onChat suppresses only the matching pending entry on THIS
    // device, so a second device on the same account still renders the message.
    if (!_chatCtrl.isClosed) {
      final me = hive.getUser();
      _chatCtrl.add(PartyChatMessage(
        userId: _myUserId ?? '',
        username: me?.username ?? me?.displayName,
        photoURL: me?.photoURL,
        text: capped,
        ts: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  void sendReaction(String emoji) {
    if (!_canEmit) return;
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;
    final capped = trimmed.length > 16 ? trimmed.substring(0, 16) : trimmed;
    final clientId = _nextClientId();
    _rememberPending(_pendingReactionIds, clientId);
    _socket.emit('party:reaction', <String, dynamic>{
      'code': _currentCode,
      'emoji': capped,
      'clientId': clientId,
    });
    // Optimistic local echo (see sendChat); own server echo dropped in
    // _onReaction by matching the pending clientId for THIS device only.
    if (!_reactionCtrl.isClosed) {
      _reactionCtrl.add(PartyReaction(
        userId: _myUserId ?? '',
        emoji: capped,
        ts: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  bool get _canEmit => _socket.connected && _currentCode != null;

  Future<bool> _openSocket({bool force = false}) async {
    final token = await tokenRefresher.ensureFresh(force: force);
    if (_disposed) return false;
    if (token == null || token.isEmpty) {
      state.value = state.value.copyWith(
        connection: PartyConnection.error,
        errorCode: 'unauthorized',
      );
      return false;
    }
    state.value = state.value.copyWith(
      connection: PartyConnection.connecting,
      myUserId: _myUserId,
    );
    _socket.connect(
      origin: _origin,
      token: token,
      photoURL: hive.getUser()?.photoURL,
    );
    return true;
  }

  void _wireSocket() {
    _socket.onConnect(_handleConnect);
    _socket.onConnectError(_handleConnectError);
    _socket.onDisconnect(_handleDisconnect);
    _socket.on('party:state', _onState);
    _socket.on('party:sync', _onSync);
    _socket.on('party:content', _onContent);
    _socket.on('party:member', _onMember);
    _socket.on('party:chat', _onChat);
    _socket.on('party:reaction', _onReaction);
    _socket.on('party:closed', _onClosed);
    _socket.on('party:error', _onErrorEvent);
  }

  void _handleConnect() {
    _handshakeRetried = false;
    state.value = state.value.copyWith(connection: PartyConnection.connected);
    // Room membership is bound to the socket — (re)join after every connect.
    final code = _currentCode;
    if (code != null) {
      _socket.emit('party:join', <String, dynamic>{'code': code});
    }
  }

  Future<void> _handleConnectError(Object error) async {
    final message = error.toString();
    if (message.contains('unauthorized') && !_handshakeRetried) {
      _handshakeRetried = true;
      final ok = await _openSocket(force: true);
      if (!ok && !_disposed) {
        state.value =
            state.value.copyWith(connection: PartyConnection.error);
      }
      return;
    }
    if (!_disposed) {
      state.value = state.value.copyWith(connection: PartyConnection.error);
    }
  }

  void _handleDisconnect() {
    if (_disposed) return;
    if (_currentCode != null && state.value.phase != PartyPhase.closed) {
      // socket.io will auto-reconnect; reflect that in the UI.
      state.value =
          state.value.copyWith(connection: PartyConnection.reconnecting);
    }
  }

  // ---------------------------------------------------------------------------
  // Server → client events
  // ---------------------------------------------------------------------------

  void _onState(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final room = PartyRoom.fromSnapshot(j);
    state.value = state.value.copyWith(
      room: room,
      phase: PartyPhase.inRoom,
      connection: PartyConnection.connected,
      myUserId: _myUserId,
      clearError: true,
    );
  }

  void _onSync(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final pbJson = _asMap(j['playback']);
    if (pbJson == null) return;
    final pb = PartyPlayback.fromJson(pbJson, receivedAt: DateTime.now());
    final room = state.value.room;
    if (room != null) {
      state.value = state.value.copyWith(room: room.copyWith(playback: pb));
    }
    if (!_syncCtrl.isClosed) _syncCtrl.add(pb);
  }

  void _onContent(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final contentJson = _asMap(j['content']);
    final content =
        contentJson != null ? PartyContent.fromJson(contentJson) : null;
    final pbJson = _asMap(j['playback']);
    final pb = pbJson != null
        ? PartyPlayback.fromJson(pbJson, receivedAt: DateTime.now())
        : null;
    final room = state.value.room;
    if (room != null) {
      state.value = state.value
          .copyWith(room: room.copyWith(content: content, playback: pb));
    }
    if (content != null && !_contentCtrl.isClosed) {
      _contentCtrl.add(content);
    }
  }

  void _onMember(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final members = PartyMember.listFrom(j['members']);
    final hostUserId = j['hostUserId'] as String?;
    final room = state.value.room;
    if (room != null) {
      state.value = state.value.copyWith(
        room: room.copyWith(members: members, hostUserId: hostUserId),
      );
    }
  }

  void _onChat(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final msg = PartyChatMessage.fromJson(j);
    // Suppress ONLY this device's own optimistic echo, matched by the clientId
    // we attached on send and the server echoed back. Never dedupe by userId
    // alone: a second device on the same account shares our account id and must
    // still render our messages.
    final clientId = j['clientId'] as String?;
    if (clientId != null) {
      if (_pendingChatIds.remove(clientId)) return;
    } else if (msg.userId.isNotEmpty && msg.userId == _myUserId) {
      // Legacy fallback for a server that doesn't echo the clientId.
      return;
    }
    if (!_chatCtrl.isClosed) _chatCtrl.add(msg);
  }

  void _onReaction(dynamic d) {
    final j = _asMap(d);
    if (j == null) return;
    final r = PartyReaction.fromJson(j);
    // Own echo matched by pending clientId only (see _onChat) — not by userId.
    final clientId = j['clientId'] as String?;
    if (clientId != null) {
      if (_pendingReactionIds.remove(clientId)) return;
    } else if (r.userId.isNotEmpty && r.userId == _myUserId) {
      return; // legacy fallback: server didn't echo the clientId
    }
    if (!_reactionCtrl.isClosed) _reactionCtrl.add(r);
  }

  void _onClosed(dynamic d) {
    final j = _asMap(d);
    final reason = j?['reason'] as String?;
    state.value = state.value.copyWith(
      phase: PartyPhase.closed,
      closedReason: reason,
    );
    _currentCode = null;
    _socket.disconnect();
  }

  void _onErrorEvent(dynamic d) {
    final j = _asMap(d);
    final code = j?['code'] as String?;
    final message = j?['message'] as String?;
    state.value = state.value.copyWith(
      errorCode: code,
      errorMessage: message,
    );
    if (!_errorCtrl.isClosed) {
      _errorCtrl.add(code ?? message ?? 'error_generic');
    }
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NOTE: shadows the `state` ValueNotifier field, which this body never uses.
    if (state == AppLifecycleState.resumed) {
      _ensureConnected();
    }
  }

  void _ensureConnected() {
    final code = _currentCode;
    if (code == null) return;
    if (_socket.connected) {
      // Defensive re-join in case membership lapsed while backgrounded.
      _socket.emit('party:join', <String, dynamic>{'code': code});
      return;
    }
    _openSocket();
  }

  static Map<String, dynamic>? _asMap(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : null;

  /// Per-send id unique to this device, round-tripped through the server so an
  /// own echo can be recognised without deduping by the shared account userId.
  String _nextClientId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_clientSeq++}';

  /// Records a pending own-send id, evicting the oldest (insertion-ordered) when
  /// the set grows — a server that drops a rate-limited message never echoes its
  /// id back, so the entry would otherwise leak.
  static void _rememberPending(Set<String> pending, String id) {
    pending.add(id);
    while (pending.length > 64) {
      pending.remove(pending.first);
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _socket.dispose();
    state.dispose();
    _chatCtrl.close();
    _reactionCtrl.close();
    _contentCtrl.close();
    _syncCtrl.close();
    _errorCtrl.close();
  }
}
