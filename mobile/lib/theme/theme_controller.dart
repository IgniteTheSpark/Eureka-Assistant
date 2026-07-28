import 'package:flutter/material.dart';

import 'app_theme.dart';
import '../theme_v2/foundation/theme_v2_semantics.dart';
import '../theme_v2/foundation/theme_v2_tokens.dart';

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
  const ThemeToggle({super.key, this.onDark = false});

  /// Light control color for the today page's dark header (see GlobalHeaderBar).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final legacy = theme.extension<EurekaTheme>();
    final v2 = theme.extension<ThemeV2Tokens>();
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, child) {
        final dark = mode == ThemeMode.dark;
        return ThemeV2IconButton(
          semanticLabel: dark ? '切换到日间' : '切换到夜间',
          onPressed: toggleThemeMode,
          icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          color: onDark
              ? Colors.white70
              : legacy?.colors.textMid ??
                    v2?.muted ??
                    theme.colorScheme.onSurfaceVariant,
        );
      },
    );
  }
}
