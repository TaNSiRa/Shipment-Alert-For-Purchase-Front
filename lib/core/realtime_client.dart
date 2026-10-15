import 'package:socket_io_client/socket_io_client.dart' as io;

/// Every event the backend broadcasts. Each one only means "something you may
/// be looking at changed — reload"; REST stays the source of truth.
const kRealtimeEvents = [
  'po.updated',
  'masters.updated',
  'workflow.updated',
  'settings.updated',
  'users.updated',
  'sections.updated',
];

class RealtimeClient {
  io.Socket? _socket;
  String? _section;

  void connect({
    required String baseUrl,
    required String token,
    required void Function(String event, dynamic data) onEvent,
  }) {
    final url = baseUrl.replaceAll(RegExp(r'/api/?$'), '');
    _socket?.dispose();
    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/ws')
          // The server verifies this JWT and derives the user from it.
          .setAuth({'token': token})
          .disableAutoConnect()
          // Without forceNew a re-login on the same tab would reuse the previous
          // user's cached socket.
          .enableForceNew()
          .build(),
    );
    for (final event in kRealtimeEvents) {
      _socket!.on(event, (data) => onEvent(event, data));
    }
    _socket!.onConnect((_) => _join());
    _socket!.connect();
  }

  /// Listen to one section's changes (the one on screen).
  void joinSection(String? code) {
    _section = code;
    _join();
  }

  void _join() => _socket?.emit('section.join', {'section': _section});

  void dispose() {
    _section = null;
    _socket?.dispose();
    _socket = null;
  }
}
