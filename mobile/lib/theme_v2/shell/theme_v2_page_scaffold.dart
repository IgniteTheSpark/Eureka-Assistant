import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import 'theme_v2_floating_dock.dart';
import 'theme_v2_global_top_nav.dart';

/// The only per-page shell declaration.
///
/// Pages provide their body and choose whether global navigation, the dock,
/// and keyboard-driven resizing apply. The app shell injects the shared chrome.
class ThemeV2PageScaffold extends StatelessWidget {
  const ThemeV2PageScaffold({
    super.key,
    required this.body,
    this.showTopNav = true,
    this.showDock = true,
    this.resizeToAvoidBottomInset = true,
    this.extendBodyBehindChrome = false,
    this.topNav,
    this.dock,
    this.companion,
    this.topNavExtent = ThemeV2GlobalTopNav.height,
  });

  final Widget body;
  final bool showTopNav;
  final bool showDock;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindChrome;
  final Widget? topNav;
  final Widget? dock;
  final Widget? companion;
  final double topNavExtent;

  ThemeV2PageScaffold withShellChrome({
    required Widget body,
    required Widget topNav,
    required Widget dock,
    Widget? companion,
  }) {
    return ThemeV2PageScaffold(
      body: body,
      showTopNav: showTopNav,
      showDock: showDock,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBodyBehindChrome: extendBodyBehindChrome,
      topNav: topNav,
      dock: dock,
      companion: companion,
      topNavExtent: topNavExtent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topClearance = showTopNav && !extendBodyBehindChrome
        ? topNavExtent
        : 0.0;
    final bottomClearance = showDock && !extendBodyBehindChrome
        ? ThemeV2FloatingDock.contentClearance +
              MediaQuery.paddingOf(context).bottom
        : 0.0;
    final composition = SafeArea(
      bottom: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: topClearance,
                bottom: bottomClearance,
              ),
              child: body,
            ),
          ),
          if (showTopNav && topNav != null)
            Positioned(left: 0, right: 0, top: 0, child: topNav!),
          if (showDock && dock != null)
            Positioned(left: 0, right: 0, bottom: 0, child: dock!),
          if (showDock && companion != null) Positioned.fill(child: companion!),
        ],
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: context.themeV2.background,
      body: composition,
    );
  }
}
