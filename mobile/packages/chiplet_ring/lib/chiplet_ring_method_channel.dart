import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chiplet_ring_platform_interface.dart';

/// An implementation of [ChipletRingPlatform] that uses method channels.
class MethodChannelChipletRing extends ChipletRingPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('chiplet_ring');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
