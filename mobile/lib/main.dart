import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'theme/app_theme.dart';
import 'theme/eureka_colors.dart';

void main() {
  runApp(const ProviderScope(child: EurekaApp()));
}

class EurekaApp extends StatelessWidget {
  const EurekaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eureka',
      debugShowCheckedModeBanner: false,
      theme: buildEurekaTheme(EurekaColors.light),
      darkTheme: buildEurekaTheme(EurekaColors.dark),
      // Default to dark (atmosphere), matching the web app's default.
      themeMode: ThemeMode.dark,
      home: const AppShell(),
    );
  }
}
