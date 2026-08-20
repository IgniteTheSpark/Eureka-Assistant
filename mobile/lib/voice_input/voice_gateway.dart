import 'dart:io';
import 'dart:typed_data';

abstract interface class VoiceGatewayConnection {
  Stream<Object?> get events;

  void sendText(String value);

  void sendBytes(Uint8List value);

  Future<void> close();
}

typedef VoiceGatewayConnector =
    Future<VoiceGatewayConnection> Function(
      Uri uri,
      Map<String, String> headers,
    );

Uri voiceGatewayUri(String apiBase) {
  final base = Uri.parse(apiBase);
  final scheme = switch (base.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    _ => throw const FormatException('API base must use HTTP or HTTPS'),
  };
  return base.replace(
    scheme: scheme,
    path: '/api/asr/stream',
    query: null,
    fragment: null,
  );
}

Future<VoiceGatewayConnection> connectVoiceGateway(
  Uri uri,
  Map<String, String> headers,
) async {
  final socket = await WebSocket.connect(uri.toString(), headers: headers);
  return IoVoiceGatewayConnection(socket);
}

final class IoVoiceGatewayConnection implements VoiceGatewayConnection {
  IoVoiceGatewayConnection(this._socket);

  final WebSocket _socket;
  bool _closed = false;

  @override
  Stream<Object?> get events => _socket;

  @override
  void sendText(String value) => _socket.add(value);

  @override
  void sendBytes(Uint8List value) => _socket.add(value);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
  }
}
