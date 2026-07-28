import 'package:flutter/widgets.dart';

import '../app_shell.dart';
import '../config.dart';

/// The app-root shell boundary for the staged Theme V2 migration.
///
/// This is the only production caller of [AppConfig.themeV2]. Keeping the
/// compile-time choice here ensures individual pages never need a rollout flag.
class AppRootShell extends StatelessWidget {
  const AppRootShell({
    super.key,
    this.legacyShell = const AppShell(),
    this.themeV2Shell = const ThemeV2AppShell(),
  });

  final Widget legacyShell;
  final Widget themeV2Shell;

  @override
  Widget build(BuildContext context) {
    return ThemeV2Rollout(
      enabled: AppConfig.themeV2,
      legacyShell: legacyShell,
      themeV2Shell: themeV2Shell,
    );
  }
}

/// App-root seam for the staged Theme V2 migration.
///
/// The decision is deliberately made once, before either shell is built. Pages
/// must not read the rollout flag: they belong to one shell or the other.
class ThemeV2Rollout extends StatelessWidget {
  const ThemeV2Rollout({
    super.key,
    this.enabled = false,
    required this.legacyShell,
    required this.themeV2Shell,
  });

  final bool enabled;
  final Widget legacyShell;
  final Widget themeV2Shell;

  @override
  Widget build(BuildContext context) {
    return enabled ? themeV2Shell : legacyShell;
  }
}
