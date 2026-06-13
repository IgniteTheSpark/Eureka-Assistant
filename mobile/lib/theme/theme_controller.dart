import 'package:flutter/material.dart';

import 'app_theme.dart';

/// App-wide theme mode. The app defaults to light; the header
/// sun/moon toggle flips it. Kept as a global ValueNotifier so any surface can
/// toggle without threading state through every widget.
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void toggleThemeMode() {
  themeModeNotifier.value =
      themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

/// Sun/moon button that flips the app theme (mirrors the web HeaderControls).
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, child) {
        final dark = mode == ThemeMode.dark;
        return IconButton(
          tooltip: dark ? '切换到日间' : '切换到夜间',
          onPressed: toggleThemeMode,
          icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: eu.textMid),
        );
      },
    );
  }
}
