import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A TV this account can drive, and whether it is actually reachable.
@immutable
class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.name,
    required this.online,
    this.lastSeenAt,
  });

  final String id;
  final String name;

  /// Holding the channel open — not "signed in recently". A linked TV that is
  /// switched off is not something you can press buttons at.
  final bool online;

  final DateTime? lastSeenAt;

  static RemoteDevice? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return RemoteDevice(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'TV',
      online: json['online'] == true,
      lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
    );
  }
}

/// What the TV last reported it was doing.
@immutable
class RemoteTvState {
  const RemoteTvState({
    this.screen,
    this.title,
    this.episode,
    this.playing = false,
    this.positionMs,
    this.durationMs,
  });

  final String? screen;
  final String? title;
  final String? episode;
  final bool playing;
  final int? positionMs;
  final int? durationMs;

  bool get hasPlayback => (durationMs ?? 0) > 0;

  static RemoteTvState? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return RemoteTvState(
      screen: json['screen'] as String?,
      title: json['title'] as String?,
      episode: json['episode']?.toString(),
      playing: json['playing'] == true,
      positionMs: (json['positionMs'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }
}

/// Raised when the TV is not holding the channel open.
///
/// Its own type because it is the one failure worth saying out loud: every
/// other error here means something went wrong, this one means "turn the TV on".
class RemoteOfflineException implements Exception {
  const RemoteOfflineException();
}

/// The phone half of the remote control.
///
/// Commands go through the server rather than the local network. The two
/// devices are frequently not on the same one, and a remote that only works at
/// home is not the feature people want.
class RemoteControlService {
  const RemoteControlService({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<RemoteDevice>> devices() async {
    final response = await _dio.get('/remote/devices');
    final items = (response.data as Map?)?['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => RemoteDevice.fromJson(e.cast<String, dynamic>()))
        .whereType<RemoteDevice>()
        .toList(growable: false);
  }

  Future<({bool online, RemoteTvState? state})> state(String deviceId) async {
    final response = await _dio.get(
      '/remote/state',
      queryParameters: {'deviceId': deviceId},
    );
    final data = response.data as Map?;
    return (
      online: data?['online'] == true,
      state: RemoteTvState.fromJson(
        (data?['state'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  /// Sends one command.
  ///
  /// A 409 is the server saying nothing is listening, which is the normal state
  /// of a TV that is off — surfaced as [RemoteOfflineException] so the UI can
  /// say so rather than showing a stack of failures.
  Future<void> send(
    String deviceId,
    String type, {
    Map<String, dynamic> args = const {},
  }) async {
    try {
      await _dio.post(
        '/remote/command',
        data: {'deviceId': deviceId, 'type': type, ...args},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) throw const RemoteOfflineException();
      rethrow;
    }
  }

  Future<void> play(String id) => send(id, 'play');
  Future<void> pause(String id) => send(id, 'pause');
  Future<void> playPause(String id) => send(id, 'playpause');
  Future<void> next(String id) => send(id, 'next');
  Future<void> previous(String id) => send(id, 'prev');
  Future<void> back(String id) => send(id, 'back');
  Future<void> home(String id) => send(id, 'home');

  Future<void> seekTo(String id, int positionMs) =>
      send(id, 'seek', args: {'positionMs': positionMs});

  Future<void> seekBy(String id, int deltaMs) =>
      send(id, 'seekBy', args: {'deltaMs': deltaMs});

  Future<void> dpad(String id, String direction) =>
      send(id, 'dpad', args: {'direction': direction});

  /// Types into the TV's search. The point of the whole feature.
  Future<void> type(String id, String text) =>
      send(id, 'text', args: {'text': text});

  /// Plays something on the TV.
  ///
  /// The TITLE travels, not the url: the two apps do not share a source
  /// registry, so a link from a provider installed here is meaningless to a TV
  /// that does not have it. The TV resolves the title against its own sources.
  Future<void> openOnTv(
    String id, {
    required String title,
    String? contentUrl,
    String? provider,
  }) =>
      send(id, 'open', args: {
        'title': title,
        if (contentUrl != null && contentUrl.isNotEmpty) 'contentUrl': contentUrl,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      });
}
