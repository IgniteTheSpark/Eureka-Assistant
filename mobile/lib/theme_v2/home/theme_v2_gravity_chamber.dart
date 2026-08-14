import 'package:flutter/material.dart';

const double themeV2HomePanelRadius = 19;

class ThemeV2GravityChamber extends StatelessWidget {
  const ThemeV2GravityChamber({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(themeV2HomePanelRadius),
        bottomRight: Radius.circular(themeV2HomePanelRadius),
      ),
      child: child,
    );
  }
}
