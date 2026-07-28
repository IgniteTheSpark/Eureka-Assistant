import 'package:flutter/material.dart';

/// Stable host for Theme V2 widget tests.
///
/// Keeping these inputs fixed makes rollout tests independent of the host
/// machine's locale, dimensions, theme preference, and animation settings.
class ThemeV2TestApp extends StatelessWidget {
  const ThemeV2TestApp({super.key, required this.child});

  static const screenSize = Size(411, 960);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(
        size: screenSize,
        devicePixelRatio: 1,
        platformBrightness: Brightness.light,
        disableAnimations: true,
        textScaler: TextScaler.noScaling,
      ),
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.light,
        home: child,
      ),
    );
  }
}
