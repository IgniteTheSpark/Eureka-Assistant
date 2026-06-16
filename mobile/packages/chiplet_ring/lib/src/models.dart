import 'dart:typed_data';
import 'package:flutter/foundation.dart';

enum RingConnState { disconnected, scanning, connecting, connected, error }

@immutable
class RingDevice {
  final String id;
  final String name;
  final int rssi;
  const RingDevice({required this.id, required this.name, required this.rssi});
  factory RingDevice.fromMap(Map m) => RingDevice(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        rssi: (m['rssi'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class RingState {
  final RingConnState conn;
  final List<RingDevice> devices;
  const RingState({required this.conn, required this.devices});
}

@immutable
class RingAudioFrame {
  final Uint8List pcm;
  final int seq;
  final int channels;
  const RingAudioFrame({required this.pcm, required this.seq, required this.channels});
  factory RingAudioFrame.fromMap(Map m) => RingAudioFrame(
        pcm: Uint8List.fromList(List<int>.from(m['pcm'] as List)),
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        channels: (m['channels'] as num?)?.toInt() ?? 1,
      );
}
