import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme/theme_controller.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_semantics.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Theme V2 ThemeData carries the matching extension and Geist fonts', () {
    final light = buildThemeV2Theme(Brightness.light);
    final dark = buildThemeV2Theme(Brightness.dark);

    expect(light.extension<ThemeV2Tokens>(), same(ThemeV2Tokens.light));
    expect(dark.extension<ThemeV2Tokens>(), same(ThemeV2Tokens.dark));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF7F9FC));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0B0D12));
    expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(dark.colorScheme.surface, const Color(0xFF121620));
    expect(
      light.textTheme.bodyMedium?.fontFamily,
      ThemeV2Typography.primaryFont,
    );
    expect(
      dark.textTheme.bodyMedium?.fontFamily,
      ThemeV2Typography.primaryFont,
    );
    expect(ThemeV2Typography.mono().fontFamily, ThemeV2Typography.monoFont);
  });

  testWidgets('hit target and icon button expose a 44px accessible action', (
    tester,
  ) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ThemeV2IconButton(
              semanticLabel: '切换主题',
              icon: Icons.dark_mode_outlined,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(ThemeV2HitTarget)),
      const Size.square(44),
    );
    expect(find.bySemanticsLabel('切换主题'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('切换主题')),
      matchesSemantics(
        label: '切换主题',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('切换主题'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('legacy theme toggle keeps its existing control color', (
    tester,
  ) async {
    ThemeV2Tokens? attachedTokens;
    EurekaTheme? attachedLegacyTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: Builder(
          builder: (context) {
            attachedTokens = Theme.of(context).extension<ThemeV2Tokens>();
            attachedLegacyTheme = Theme.of(context).extension<EurekaTheme>();
            return const Scaffold(body: ThemeToggle());
          },
        ),
      ),
    );

    expect(attachedLegacyTheme, isNotNull);
    expect(attachedTokens, same(ThemeV2Tokens.light));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(ThemeToggle),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.color, EurekaColors.light.textMid);
  });

  testWidgets('theme toggling preserves navigator and page state', (
    tester,
  ) async {
    themeModeNotifier.value = ThemeMode.light;
    addTearDown(() => themeModeNotifier.value = ThemeMode.light);
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, child) => MaterialApp(
          navigatorKey: navigatorKey,
          theme: buildThemeV2Theme(Brightness.light),
          darkTheme: buildThemeV2Theme(Brightness.dark),
          themeMode: mode,
          home: child,
        ),
        child: const _StateProbe(),
      ),
    );

    await tester.tap(find.text('increment'));
    await tester.pump();
    expect(find.text('count: 1'), findsOneWidget);

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('second route')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('second route'), findsOneWidget);

    toggleThemeMode();
    await tester.pumpAndSettle();
    expect(themeModeNotifier.value, ThemeMode.dark);
    expect(find.text('second route'), findsOneWidget);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);
  });
}

class _StateProbe extends StatefulWidget {
  const _StateProbe();

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('count: $_count'),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: const Text('increment'),
          ),
        ],
      ),
    );
  }
}
