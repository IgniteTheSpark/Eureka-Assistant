import 'package:eureka/theme_v2/asset/asset_card.dart';
import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RichCard divider begins after the mark and keeps three values', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 375,
          child: ThemeV2AssetCard(
            variant: AssetCardVariant.richCard,
            data: AssetCardViewData(
              mark: '🎾',
              skillLabel: '网球对局',
              primaryValue: 'Kevin',
              secondaryValues: ['胜', '4–1', '深云体育公园'],
            ),
          ),
        ),
      ),
    );

    final mark = tester.getRect(find.byKey(const ValueKey('asset-card-mark')));
    final divider = tester.getRect(
      find.byKey(const ValueKey('asset-card-divider')),
    );
    expect(divider.left, greaterThan(mark.right));
    expect(
      find.byKey(const ValueKey('asset-card-secondary-2')),
      findsOneWidget,
    );
  });

  testWidgets('RichCard omits divider and second row without metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 375,
          child: ThemeV2AssetCard(
            variant: AssetCardVariant.richCard,
            data: AssetCardViewData(
              mark: '✍️',
              skillLabel: '笔记',
              primaryValue: '只有标题',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('asset-card-divider')), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-card-secondary-row')),
      findsNothing,
    );
  });

  testWidgets('86px RichCard uses the compact 40px mark geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 371,
          child: ThemeV2AssetCard(
            variant: AssetCardVariant.richCard,
            height: 86,
            data: AssetCardViewData(
              mark: '🎾',
              skillLabel: '网球对局',
              primaryValue: 'Kevin',
              secondaryValues: ['胜', '4–1'],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('asset-card-mark'))),
      const Size.square(40),
    );
  });

  testWidgets('MinimalRow shows context time, mark, skill, and primary only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 375,
          child: ThemeV2AssetCard(
            variant: AssetCardVariant.minimalRow,
            data: AssetCardViewData(
              mark: '🎾',
              skillLabel: '网球对局',
              primaryValue: 'Kevin',
              secondaryValues: ['胜', '4–1'],
              timeLabel: '19:30',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('asset-card-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-mark')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-skill')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-primary')), findsOneWidget);
    expect(find.text('胜'), findsNothing);
    expect(find.byKey(const ValueKey('asset-card-divider')), findsNothing);
  });

  testWidgets('MinimalLine shows only skill and primary on one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 180,
          child: ThemeV2AssetCard(
            variant: AssetCardVariant.minimalLine,
            data: AssetCardViewData(
              mark: '🎾',
              skillLabel: '网球对局',
              primaryValue: 'Kevin',
              secondaryValues: ['胜'],
              timeLabel: '19:30',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('asset-card-skill')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-mark')), findsNothing);
    expect(find.byKey(const ValueKey('asset-card-time')), findsNothing);
    expect(find.text('胜'), findsNothing);
  });

  testWidgets('IconTime shows only the asset mark and localized time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ThemeV2AssetCard(
          variant: AssetCardVariant.iconTime,
          data: AssetCardViewData(
            mark: '🎾',
            skillLabel: '网球对局',
            primaryValue: 'Kevin',
            secondaryValues: ['胜'],
            timeLabel: '21:34',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('asset-card-mark')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-card-skill')), findsNothing);
    expect(find.byKey(const ValueKey('asset-card-primary')), findsNothing);
    expect(find.text('Kevin'), findsNothing);
  });

  testWidgets('enabled card exposes one semantic button and opens on tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opens = 0;
    await tester.pumpWidget(
      _host(
        ThemeV2AssetCard(
          variant: AssetCardVariant.richCard,
          data: const AssetCardViewData(
            mark: '🎾',
            skillLabel: '网球对局',
            primaryValue: 'Kevin',
          ),
          onOpen: () => opens++,
        ),
      ),
    );

    final target = find.bySemanticsLabel('打开网球对局：Kevin');
    expect(target, findsOneWidget);
    expect(
      tester.getSemantics(target),
      matchesSemantics(
        label: '打开网球对局：Kevin',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(target);
    expect(opens, 1);
    semantics.dispose();
  });

  testWidgets('disabled card exposes no tap action and ignores taps', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opens = 0;
    await tester.pumpWidget(
      _host(
        ThemeV2AssetCard(
          variant: AssetCardVariant.richCard,
          data: const AssetCardViewData(
            mark: '🎾',
            skillLabel: '网球对局',
            primaryValue: 'Kevin',
          ),
          disabled: true,
          onOpen: () => opens++,
        ),
      ),
    );

    final target = find.bySemanticsLabel('打开网球对局：Kevin');
    expect(target, findsOneWidget);
    expect(
      tester.getSemantics(target),
      matchesSemantics(
        label: '打开网球对局：Kevin',
        isButton: true,
        isEnabled: false,
        hasEnabledState: true,
        hasTapAction: false,
      ),
    );

    await tester.tap(target);
    expect(opens, 0);
    semantics.dispose();
  });

  testWidgets('RichCard stays bounded on a narrow surface and caps metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 320,
          child: ThemeV2AssetCard(
            variant: AssetCardVariant.richCard,
            data: AssetCardViewData(
              mark: '🎾',
              skillLabel: '网球对局',
              primaryValue: '一场名字非常长但仍需要被单行截断的晚间网球对局',
              secondaryValues: [
                '一个非常长的比赛结果',
                '四比一并且包含很长的说明',
                '深圳湾体育中心室外第十二号球场',
                '第四个字段不应该显示',
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('asset-card-secondary-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('asset-card-secondary-3')), findsNothing);
  });

  testWidgets('press feedback scales an enabled card to 0.98', (tester) async {
    await tester.pumpWidget(
      _host(
        ThemeV2AssetCard(
          variant: AssetCardVariant.richCard,
          data: const AssetCardViewData(
            mark: '🎾',
            skillLabel: '网球对局',
            primaryValue: 'Kevin',
          ),
          onOpen: () {},
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ThemeV2AssetCard)),
    );
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('asset-card-press-transform')),
          )
          .scale,
      0.98,
    );

    await gesture.up();
  });

  testWidgets('reduced motion keeps press feedback at a static scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ThemeV2AssetCard(
          variant: AssetCardVariant.richCard,
          data: const AssetCardViewData(
            mark: '🎾',
            skillLabel: '网球对局',
            primaryValue: 'Kevin',
          ),
          onOpen: () {},
        ),
        disableAnimations: true,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ThemeV2AssetCard)),
    );
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('asset-card-press-transform')),
          )
          .scale,
      1,
    );

    await gesture.up();
  });
}

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);
