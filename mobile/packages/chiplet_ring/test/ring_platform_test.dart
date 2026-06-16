import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/src/ring_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chiplet_ring/methods');
  final calls = <String>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  test('startScan/connect/startRecording invoke expected method names', () async {
    final p = RingPlatform();
    await p.startScan();
    await p.connect('AA:BB');
    await p.startRecording();
    await p.stopRecording();
    await p.disconnect();
    expect(calls, ['startScan', 'connect', 'startRecording', 'stopRecording', 'disconnect']);
  });
}
