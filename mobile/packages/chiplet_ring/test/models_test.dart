import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/src/models.dart';

void main() {
  test('RingDevice.fromMap parses fields', () {
    final d = RingDevice.fromMap({'id': 'AA:BB', 'name': 'Ring', 'rssi': -55});
    expect(d.id, 'AA:BB');
    expect(d.name, 'Ring');
    expect(d.rssi, -55);
  });

  test('RingAudioFrame.fromMap parses pcm bytes + seq + channels', () {
    final f = RingAudioFrame.fromMap({
      'pcm': [1, 2, 3, 4],
      'seq': 7,
      'channels': 1,
    });
    expect(f.pcm, [1, 2, 3, 4]);
    expect(f.seq, 7);
    expect(f.channels, 1);
  });

  test('RingState.disconnected has empty devices', () {
    const s = RingState(conn: RingConnState.disconnected, devices: []);
    expect(s.conn, RingConnState.disconnected);
    expect(s.devices, isEmpty);
  });
}
