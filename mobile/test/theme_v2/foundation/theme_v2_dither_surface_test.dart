import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_dither_surface.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Calendar and Library presets match the approved motion contract', () {
    const calendar = ThemeV2DitherFieldConfig.calendar();
    const library = ThemeV2DitherFieldConfig.library();

    expect(calendar.pixelSize, 4);
    expect(calendar.colorNum, 4);
    expect(calendar.waveAmplitude, .24);
    expect(calendar.waveFrequency, 2.8);
    expect(calendar.waveSpeed, .035);
    expect(calendar.flowDirection, const Offset(1, .08));
    expect(calendar.displacementStrength, .84);

    expect(library.pixelSize, 4);
    expect(library.colorNum, 4);
    expect(library.waveAmplitude, .24);
    expect(library.waveFrequency, 2.6);
    expect(library.waveSpeed, .028);
    expect(library.flowDirection, const Offset(.1, 1));
    expect(library.displacementStrength, .84);
  });

  test(
    'source selection is visible, deterministic, prioritized, and capped',
    () {
      final selected = selectThemeV2DitherRegistrations(
        registrations: const [
          ThemeV2DitherRegistration(
            id: 'z',
            rect: Rect.fromLTWH(45, 45, 10, 10),
            shape: ThemeV2DitherSourceShape.capsule,
          ),
          ThemeV2DitherRegistration(
            id: 'a',
            rect: Rect.fromLTWH(45, 45, 10, 10),
            shape: ThemeV2DitherSourceShape.capsule,
          ),
          ThemeV2DitherRegistration(
            id: 'priority',
            rect: Rect.fromLTWH(0, 0, 10, 10),
            shape: ThemeV2DitherSourceShape.circle,
            priority: 10,
          ),
          ThemeV2DitherRegistration(
            id: 'offscreen',
            rect: Rect.fromLTWH(120, 120, 10, 10),
            shape: ThemeV2DitherSourceShape.circle,
            priority: 100,
          ),
        ],
        viewport: const Rect.fromLTWH(0, 0, 100, 100),
        limit: 2,
      );

      expect(selected.map((source) => source.id), ['priority', 'a']);
    },
  );

  testWidgets('surface converts a visible reporter into one local source', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 200,
          height: 200,
          child: ThemeV2DitherSurface(
            active: true,
            config: ThemeV2DitherFieldConfig.calendar(),
            child: Align(
              alignment: Alignment.topLeft,
              child: ThemeV2DitherSourceReporter(
                id: 'record',
                shape: ThemeV2DitherSourceShape.capsule,
                child: SizedBox(width: 80, height: 40),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final field = tester.widget<ThemeV2DitherField>(
      find.byType(ThemeV2DitherField),
    );
    expect(field.sources, hasLength(1));
    expect(field.sources.single.center, const Offset(40, 20));
    expect(field.sources.single.size, const Size(80, 40));
    expect(field.sources.single.energy, 0);
  });

  testWidgets('surface pauses without losing phase when inactive', (
    tester,
  ) async {
    Widget surface(bool active) => _host(
      ThemeV2DitherSurface(
        active: active,
        config: const ThemeV2DitherFieldConfig.calendar(),
        child: const SizedBox.expand(),
      ),
    );

    await tester.pumpWidget(surface(true));
    final running =
        tester
                .widget<ThemeV2DitherField>(find.byType(ThemeV2DitherField))
                .motion!
            as AnimationController;
    await tester.pump(const Duration(milliseconds: 40));
    final phase = running.value;
    expect(running.isAnimating, isTrue);

    await tester.pumpWidget(surface(false));
    expect(running.isAnimating, isFalse);
    expect(running.value, phase);
  });

  testWidgets('Reduce Motion freezes phase and dark mode uses .26 opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.dark),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ThemeV2DitherSurface(
            active: true,
            config: ThemeV2DitherFieldConfig.library(),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );

    final field = tester.widget<ThemeV2DitherField>(
      find.byType(ThemeV2DitherField),
    );
    expect(field.reduceMotion, isTrue);
    expect(field.config.opacity, .26);
    expect((field.motion! as AnimationController).isAnimating, isFalse);
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);
