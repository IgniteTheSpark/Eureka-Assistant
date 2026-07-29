import 'dart:io';

import 'package:eureka/theme_v2/asset/asset_card.dart';
import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surface = ValueKey('asset-card-golden-surface');

  setUpAll(() async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'))).load();
    await (FontLoader('Geist Mono')..addFont(
          rootBundle.load('assets/fonts/GeistMono/GeistMono-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();

    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    if (pingFang.existsSync()) {
      await (FontLoader(
        'PingFang SC',
      )..addFont(pingFang.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  Future<void> pumpGolden(
    WidgetTester tester, {
    required Brightness brightness,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 960);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final tokens = ThemeV2Tokens.forBrightness(brightness);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(brightness),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: RepaintBoundary(
              key: surface,
              child: ColoredBox(
                color: tokens.background,
                child: const SafeArea(child: _AssetCardShowcase()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('shared card family 411 $suffix', (tester) async {
      await pumpGolden(tester, brightness: brightness);

      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/asset-card-family-411-$suffix.png'),
      );
    });
  }
}

class _AssetCardShowcase extends StatelessWidget {
  const _AssetCardShowcase();

  static const tennis = AssetCardViewData(
    mark: '球',
    skillLabel: '网球对局',
    primaryValue: 'Kevin',
    secondaryValues: ['胜', '4–1', '深云体育公园'],
    timeLabel: '19:30',
  );

  static const note = AssetCardViewData(
    mark: '记',
    skillLabel: '笔记',
    primaryValue: '记录今晚关于资产卡片结构的几个想法',
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ASSET CARDS',
            style: TextStyle(
              color: tokens.muted,
              fontFamily: 'Geist Mono',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          const _SectionLabel('RICH / 96'),
          const SizedBox(height: 8),
          const ThemeV2AssetCard(
            variant: AssetCardVariant.richCard,
            data: tennis,
          ),
          const SizedBox(height: 18),
          const _SectionLabel('RICH / 86 · EDIT PREVIEW'),
          const SizedBox(height: 8),
          const ThemeV2AssetCard(
            variant: AssetCardVariant.richCard,
            height: 86,
            data: AssetCardViewData(
              mark: '账',
              skillLabel: '消费记录',
              primaryValue: '晚餐',
              secondaryValues: ['¥ 128.00', '餐饮', '深圳湾万象城'],
            ),
          ),
          const SizedBox(height: 18),
          const _SectionLabel('RICH · PRIMARY ONLY'),
          const SizedBox(height: 8),
          const ThemeV2AssetCard(
            variant: AssetCardVariant.richCard,
            data: note,
          ),
          const SizedBox(height: 18),
          const _SectionLabel('MINIMAL ROW'),
          const SizedBox(height: 8),
          const ThemeV2AssetCard(
            variant: AssetCardVariant.minimalRow,
            data: tennis,
          ),
          const SizedBox(height: 18),
          const _SectionLabel('MINIMAL LINE'),
          const SizedBox(height: 8),
          const ThemeV2AssetCard(
            variant: AssetCardVariant.minimalLine,
            data: tennis,
          ),
          const SizedBox(height: 18),
          const _SectionLabel('ICON + TIME'),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: _IconTimeFixture(mark: '待', time: '08:15'),
              ),
              Expanded(
                child: _IconTimeFixture(mark: '记', time: '10:20'),
              ),
              Expanded(
                child: _IconTimeFixture(mark: '球', time: '19:30'),
              ),
              Expanded(
                child: _IconTimeFixture(mark: '账', time: '21:05'),
              ),
              Expanded(
                child: _IconTimeFixture(mark: '书', time: '22:10'),
              ),
              Expanded(
                child: _IconTimeFixture(mark: '闪', time: '23:00'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.themeV2.muted,
        fontFamily: 'Geist Mono',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _IconTimeFixture extends StatelessWidget {
  const _IconTimeFixture({required this.mark, required this.time});

  final String mark;
  final String time;

  @override
  Widget build(BuildContext context) {
    return ThemeV2AssetCard(
      variant: AssetCardVariant.iconTime,
      data: AssetCardViewData(
        mark: mark,
        skillLabel: '资产',
        primaryValue: '示例',
        timeLabel: time,
      ),
    );
  }
}
