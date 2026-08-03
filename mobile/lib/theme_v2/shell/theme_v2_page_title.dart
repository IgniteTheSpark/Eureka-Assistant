import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';

class ThemeV2PageTitle extends StatelessWidget {
  const ThemeV2PageTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: TextStyle(
          color: context.themeV2.foreground,
          fontFamily: 'Geist',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
        ),
      ),
    );
  }
}
