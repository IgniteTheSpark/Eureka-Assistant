import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'chiplet_ring_method_channel.dart';

abstract class ChipletRingPlatform extends PlatformInterface {
  /// Constructs a ChipletRingPlatform.
  ChipletRingPlatform() : super(token: _token);

  static final Object _token = Object();

  static ChipletRingPlatform _instance = MethodChannelChipletRing();

  /// The default instance of [ChipletRingPlatform] to use.
  ///
  /// Defaults to [MethodChannelChipletRing].
  static ChipletRingPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ChipletRingPlatform] when
  /// they register themselves.
  static set instance(ChipletRingPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
