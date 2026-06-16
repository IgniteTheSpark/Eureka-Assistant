import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:chiplet_ring/chiplet_ring_platform_interface.dart';
import 'package:chiplet_ring/chiplet_ring_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockChipletRingPlatform
    with MockPlatformInterfaceMixin
    implements ChipletRingPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ChipletRingPlatform initialPlatform = ChipletRingPlatform.instance;

  test('$MethodChannelChipletRing is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelChipletRing>());
  });

  test('getPlatformVersion', () async {
    ChipletRing chipletRingPlugin = ChipletRing();
    MockChipletRingPlatform fakePlatform = MockChipletRingPlatform();
    ChipletRingPlatform.instance = fakePlatform;

    expect(await chipletRingPlugin.getPlatformVersion(), '42');
  });
}
