import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../foundation/theme_v2_theme.dart';
import '../shell/device_status_summary.dart';
import 'theme_v2_card_device_detail_page.dart';
import 'theme_v2_ring_device_detail_page.dart';

Widget themeV2DeviceDetailPage(ThemeV2DeviceTarget target) => switch (target) {
  ThemeV2DeviceTarget.card => const ThemeV2CardDeviceDetailPage(),
  ThemeV2DeviceTarget.ring => const ThemeV2RingDeviceDetailPage(),
  ThemeV2DeviceTarget.pairing => throw ArgumentError.value(
    target,
    'target',
    'Pairing does not have a device detail page',
  ),
};

MaterialPageRoute<T> themeV2Route<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final originLegacyTheme = Theme.of(context).extension<EurekaTheme>();
  return MaterialPageRoute<T>(
    builder: (routeContext) {
      final ambientTheme = Theme.of(routeContext);
      var routeTheme = buildThemeV2Theme(ambientTheme.brightness);
      final legacyTheme =
          ambientTheme.extension<EurekaTheme>() ?? originLegacyTheme;
      if (legacyTheme != null) {
        routeTheme = routeTheme.copyWith(
          extensions: [...routeTheme.extensions.values, legacyTheme],
        );
      }
      return Theme(data: routeTheme, child: builder(routeContext));
    },
  );
}

MaterialPageRoute<void> themeV2DeviceRoute({
  required BuildContext context,
  required ThemeV2DeviceTarget target,
}) => themeV2Route<void>(
  context: context,
  builder: (_) => themeV2DeviceDetailPage(target),
);
