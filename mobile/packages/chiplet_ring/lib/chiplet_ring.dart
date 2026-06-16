
import 'chiplet_ring_platform_interface.dart';

class ChipletRing {
  Future<String?> getPlatformVersion() {
    return ChipletRingPlatform.instance.getPlatformVersion();
  }
}
