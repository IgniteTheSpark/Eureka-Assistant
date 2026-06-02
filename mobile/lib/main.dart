import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      home: const _ThemePreview(),
    );
  }
}

/// Temporary E1 home — verifies the ported palette renders. Replaced by the
/// real app shell (dock + Chat/Calendar/Library/Notifications) in the next step.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    Widget swatch(String name, Color c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: eu.border),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, style: TextStyle(color: eu.textLo, fontSize: 11)),
          ],
        );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Eureka',
                  style: TextStyle(
                      color: eu.brand, fontSize: 34, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Flutter E1 · theme online',
                  style: TextStyle(color: eu.textMid, fontSize: 14)),
              const SizedBox(height: 28),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  swatch('brand', eu.brand),
                  swatch('blue', eu.accentBlue),
                  swatch('amber', eu.accentAmber),
                  swatch('green', eu.accentGreen),
                  swatch('purple', eu.accentPurple),
                  swatch('red', eu.accentRed),
                  swatch('surface', eu.surfaceRaised),
                ],
              ),
              const SizedBox(height: 28),
              Text('文本 textHi 主标题',
                  style: TextStyle(color: eu.textHi, fontSize: 16, fontWeight: FontWeight.w600)),
              Text('文本 text 正文', style: TextStyle(color: eu.text, fontSize: 14)),
              Text('文本 textLo 辅助', style: TextStyle(color: eu.textLo, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
