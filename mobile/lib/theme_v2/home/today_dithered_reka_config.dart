import 'package:flutter/foundation.dart';

@immutable
class TodayDitheredRekaConfig {
  const TodayDitheredRekaConfig({
    this.renderExtent = 248,
    this.hitExtent = 200,
    this.maxTiltDegrees = 8,
    this.ditherGridSize = 4,
    this.pixelSizeRatio = 1,
    this.maxDevicePixelRatio = 2,
  }) : assert(renderExtent >= hitExtent),
       assert(hitExtent >= 64),
       assert(maxTiltDegrees > 0),
       assert(ditherGridSize > 0),
       assert(pixelSizeRatio >= 1),
       assert(maxDevicePixelRatio >= 1);

  final double renderExtent;
  final double hitExtent;
  final double maxTiltDegrees;
  final double ditherGridSize;
  final double pixelSizeRatio;
  final double maxDevicePixelRatio;

  Map<String, Object?> rendererOptions({required bool reduceMotion}) => {
    'gridSize': ditherGridSize,
    'pixelSizeRatio': pixelSizeRatio,
    'maxDpr': maxDevicePixelRatio,
    'reduceMotion': reduceMotion,
  };
}
