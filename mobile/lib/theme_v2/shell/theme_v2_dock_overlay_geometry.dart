import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme_v2_floating_dock.dart';

abstract final class ThemeV2DockOverlayGeometry {
  static const Size rekaVisibleSize = Size(78, 54);
  static const double rekaTargetExtent = 72;
  static const double centerLiftAboveDock = 12;
  static const double contentExclusionExtent = rekaTargetExtent;

  static Offset rekaCenter(Size viewport, double safeBottom) => Offset(
    viewport.width / 2,
    viewport.height -
        math.max(safeBottom, ThemeV2FloatingDock.viewportBottomPadding) -
        ThemeV2FloatingDock.shellSize.height -
        centerLiftAboveDock,
  );
}
