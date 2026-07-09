import 'package:socket_io_client/socket_io_client.dart' as sio;

/// Wraps the socket.io client for the `/watch` namespace.
///
/// Callbacks are registered once (by [WatchPartyService]) and stored here so
/// that every [connect] — including a fresh-handshake reconnect after a token
/// refresh — re-attaches them to the newly created socket. socket.io's own
/// auto-reconnection keeps the same instance and preserves handlers between
/// transient drops.
class WatchPartySocketClient {
  sio.Socket? _socket;

  void Function()? _onConnect;
  void Function(Object error)? _onConnectError;
  void Function()? _onDisconnect;
  final Map<String, void Function(dynamic data)> _listeners =
      <String, void Function(dynamic)>{};

  bool get connected => _socket?.connected ?? false;

  void onConnect(void Function() cb) => _onConnect = cb;
  void onConnectError(void Function(Object error) cb) => _onConnectError = cb;
  void onDisconnect(void Function() cb) => _onDisconnect = cb;
  void on(String event, void Function(dynamic data) cb) =>
      _listeners[event] = cb;

  /// (Re)creates the socket with a fresh handshake and connects.
  void connect({
    required String origin,
    required String token,
    String? photoURL,
  }) {
    _teardownSocket();
    final socket = sio.io(
      '$origin/watch',
      sio.OptionBuilder()
          .setTransports(<String>['websocket'])
          .setAuth(<String, dynamic>{
            'token': token,
            'photoURL': ?photoURL,
          })
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );

    final onConnect = _onConnect;
    if (onConnect != null) socket.onConnect((dynamic _) => onConnect());
    final onConnectError = _onConnectError;
    if (onConnectError != null) {
      socket.onConnectError(
        (dynamic e) => onConnectError(e ?? 'connect_error'),
      );
    }
    final onDisconnect = _onDisconnect;
    if (onDisconnect != null) socket.onDisconnect((dynamic _) => onDisconnect());
    _listeners.forEach(socket.on);

    _socket = socket;
    socket.connect();
  }

  void emit(String event, Object data) {
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit(event, data);
    }
  }

  void disconnect() => _socket?.disconnect();

  void _teardownSocket() {
    final socket = _socket;
    if (socket != null) {
      socket.dispose();
      _socket = null;
    }
  }

  void dispose() {
    _teardownSocket();
    _listeners.clear();
    _onConnect = null;
    _onConnectError = null;
    _onDisconnect = null;
  }
}
