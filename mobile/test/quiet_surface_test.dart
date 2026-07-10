import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme/ureka_tokens.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/widgets/quiet_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quiet warm tokens expose paper surfaces for light and dark themes', () {
    expect(EurekaColors.light.bg, const Color(0xFFF6F4EF));
    expect(EurekaColors.light.surface, const Color(0xFFFFFFFF));
    expect(EurekaColors.light.surfaceRaised, const Color(0xFFFBFAF7));
    expect(EurekaColors.dark.bg, const Color(0xFF0B0D10));
    expect(EurekaColors.dark.surface, const Color(0xFF13161A));
  });

  test('quiet surface defaults to neutral tile texture', () {
    const child = SizedBox(width: 10, height: 10);
    final surface = UQuietSurface(
      signalColor: const Color(0xFF8AB4FF),
      child: child,
    );

    expect(surface.padding, USpacing.cardPadding);
    expect(surface.radius, URadii.card);
    expect(surface.child, child);
  });

  testWidgets('quiet surface paints a tray with a paper core', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const Scaffold(
          body: UQuietSurface(
            signalColor: Color(0xFF8AB4FF),
            child: Text('Library tile'),
          ),
        ),
      ),
    );

    final decoratedBoxDecorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(UQuietSurface),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((w) => w.decoration)
        .whereType<BoxDecoration>();
    final containerDecorations = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(UQuietSurface),
            matching: find.byType(Container),
          ),
        )
        .map((w) => w.decoration)
        .whereType<BoxDecoration>();
    final decorations = [...decoratedBoxDecorations, ...containerDecorations];

    expect(decorations.any((d) => d.color == const Color(0xFFECE7DD)), isTrue);
    expect(decorations.any((d) => d.color == const Color(0xFFFFFEFB)), isTrue);
    expect(
      decorations.any((d) => d.color == EurekaColors.light.accentBlue),
      isFalse,
    );
  });

  testWidgets('asset card shell uses neutral surface instead of accent fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const Scaffold(
          body: CardPreview(
            CardData(
              layout: 'horizontal',
              icon: '💡',
              accentColor: 'blue',
              title: '跑步训练',
              subtitle: '5km',
              metaFields: [],
            ),
          ),
        ),
      ),
    );

    final decoratedBoxes = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .toList();

    expect(
      decoratedBoxes.any((d) => d.color == const Color(0xFFFFFEFB)),
      isTrue,
    );
    expect(
      decoratedBoxes.any(
        (d) => d.color == EurekaColors.light.accentBlue.withValues(alpha: 0.12),
      ),
      isFalse,
    );
  });

  testWidgets(
    'horizontal asset card keeps domain tag and flattens meta badges',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: const Scaffold(
            body: CardPreview(
              CardData(
                layout: 'horizontal',
                icon: '💰',
                accentColor: 'green',
                title: '午饭 38 元',
                subtitle: '餐饮',
                metaFields: [(value: '支付宝', format: 'badge')],
                domain: '生活',
              ),
            ),
          ),
        ),
      );

      expect(find.text('生活'), findsOneWidget);
      expect(find.textContaining('餐饮 · 支付宝'), findsOneWidget);

      final decoratedBoxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .toList();
      expect(
        decoratedBoxes.any(
          (d) =>
              d.color == EurekaColors.light.accentGreen.withValues(alpha: 0.12),
        ),
        isFalse,
      );
    },
  );
}
