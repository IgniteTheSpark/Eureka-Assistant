import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import 'theme_v2_floating_dock.dart';

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
  });

  final Widget body;
  final bool showTopNav;
  final bool showDock;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindChrome;
  final Widget? topNav;
  final Widget? dock;

  ThemeV2PageScaffold withShellChrome({
    required Widget body,
    required Widget topNav,
    required Widget dock,
  }) {
    return ThemeV2PageScaffold(
      body: body,
      showTopNav: showTopNav,
      showDock: showDock,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBodyBehindChrome: extendBodyBehindChrome,
      topNav: topNav,
      dock: dock,
    );
  }

  @override
  Widget build(BuildContext context) {
    final extendedBody = SafeArea(
      bottom: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (showTopNav && topNav != null)
            Positioned(left: 0, right: 0, top: 0, child: topNav!),
          if (showDock && dock != null)
            Positioned(left: 0, right: 0, bottom: 0, child: dock!),
        ],
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: context.themeV2.background,
      body: extendBodyBehindChrome
          ? extendedBody
          : SafeArea(
              bottom: false,
              child: Column(
                children: [
                  if (showTopNav && topNav != null) topNav!,
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: showDock
                                  ? ThemeV2FloatingDock.contentClearance +
                                        MediaQuery.paddingOf(context).bottom
                                  : 0,
                            ),
                            child: body,
                          ),
                        ),
                        if (showDock && dock != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: dock!,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
