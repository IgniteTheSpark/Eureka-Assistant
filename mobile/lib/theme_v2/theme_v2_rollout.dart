import 'package:flutter/widgets.dart';

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
