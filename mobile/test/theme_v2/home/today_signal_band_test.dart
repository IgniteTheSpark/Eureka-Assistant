import 'dart:async';

import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:eureka/theme_v2/home/today_dither_material.dart';
import 'package:eureka/theme_v2/home/today_region_watermark.dart';
import 'package:eureka/theme_v2/home/today_signal_band.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('five Signals occupy three lanes without duplicating content', (
    tester,
  ) async {
    final motion = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 120),
    )..value = .2;
    addTearDown(motion.dispose);
    final items = List.generate(5, _signal);

    await tester.pumpWidget(
      _host(
        TodaySignalBand(
          items: items,
          motion: motion,
          onOpenSignal: (_) async {},
        ),
      ),
    );

    for (var lane = 0; lane < 3; lane++) {
      expect(find.byKey(ValueKey('today-signal-lane-$lane')), findsOneWidget);
    }
    for (final item in items) {
      expect(find.text(item.title), findsOneWidget);
    }
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Reka 发现'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(
      find.byKey(const ValueKey('today-signal-dither-field')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TodayDitherMaterial &&
            widget.shape == TodayDitherShape.strip,
      ),
      findsNothing,
    );
    final field = tester.widget<ThemeV2DitherField>(
      find.byKey(const ValueKey('today-signal-dither-field')),
    );
    expect(field.sources, hasLength(items.length));
    expect(field.config.opacity, greaterThanOrEqualTo(.30));
  });

  testWidgets(
    'birth clears only the first lane while other lanes keep moving',
    (tester) async {
      final motion = AnimationController(
        vsync: tester,
        duration: const Duration(seconds: 120),
      )..value = .12;
      addTearDown(motion.dispose);

      await tester.pumpWidget(
        _host(
          TodaySignalBand(
            items: List.generate(6, _signal),
            motion: motion,
            birthState: TodaySignalBirthState.clearing,
            birthSignalId: 'signal-5',
            onOpenSignal: (_) async {},
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('today-signal-lane-0-cleared')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-signal-lane-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-signal-lane-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-signal-signal-5')), findsNothing);
    },
  );

  testWidgets('existing Signals keep their positions after list refresh', (
    tester,
  ) async {
    final motion = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 120),
    )..value = .3;
    addTearDown(motion.dispose);
    late StateSetter update;
    var items = List.generate(6, _signal);
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return TodaySignalBand(
              items: items,
              motion: motion,
              onOpenSignal: (_) async {},
            );
          },
        ),
      ),
    );
    final before = {
      for (final item in items)
        item.id: tester.getCenter(
          find.byKey(ValueKey('today-signal-${item.id}')),
        ),
    };

    update(() => items = List.generate(9, _signal));
    await tester.pump();

    for (final entry in before.entries) {
      final after = tester.getCenter(
        find.byKey(ValueKey('today-signal-${entry.key}')),
      );
      expect(after.dx, closeTo(entry.value.dx, .01), reason: entry.key);
      expect(after.dy, entry.value.dy, reason: entry.key);
    }
  });

  testWidgets('motion moves strips left to right while Reduce Motion freezes', (
    tester,
  ) async {
    final motion = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 120),
    )..value = .1;
    addTearDown(motion.dispose);
    final item = _signal(0);
    await tester.pumpWidget(
      _host(
        TodaySignalBand(
          items: [item],
          motion: motion,
          onOpenSignal: (_) async {},
        ),
      ),
    );
    final before = tester.getCenter(find.text(item.title));
    motion.value = .2;
    await tester.pump();
    final after = tester.getCenter(find.text(item.title));
    expect(after.dx, isNot(before.dx));

    await tester.pumpWidget(
      _host(
        TodaySignalBand(
          items: [item],
          motion: motion,
          onOpenSignal: (_) async {},
        ),
        reduceMotion: true,
      ),
    );
    final frozen = tester.getCenter(find.text(item.title));
    motion.value = .4;
    await tester.pump();
    expect(tester.getCenter(find.text(item.title)), frozen);
  });

  testWidgets('opening a Signal pauses only that strip until detail closes', (
    tester,
  ) async {
    final motion = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 120),
    )..value = .05;
    addTearDown(motion.dispose);
    final detail = Completer<void>();
    final item = _signal(0);
    await tester.pumpWidget(
      _host(
        TodaySignalBand(
          items: [item],
          motion: motion,
          onOpenSignal: (_) => detail.future,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('today-signal-signal-0')));
    await tester.pump();
    final paused = tester.getCenter(find.text(item.title));
    motion.value = .3;
    await tester.pump();
    expect(tester.getCenter(find.text(item.title)), paused);

    detail.complete();
    await tester.pump();
    motion.value = .4;
    await tester.pump();
    expect(tester.getCenter(find.text(item.title)).dx, isNot(paused.dx));
  });

  testWidgets('discovery watermark opens all without replacing item opening', (
    tester,
  ) async {
    var openAllCalls = 0;
    var openSignalCalls = 0;
    final item = _signal(0);
    await tester.pumpWidget(
      _host(
        TodaySignalBand(
          items: [item],
          onOpenAll: () => openAllCalls++,
          onOpenSignal: (_) async => openSignalCalls++,
        ),
        reduceMotion: true,
      ),
    );

    expect(find.bySemanticsLabel('查看全部 Reka 发现'), findsOneWidget);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('Reka 发现'));
    expect(openAllCalls, 2);
    expect(openSignalCalls, 0);

    final strip = find.byKey(const ValueKey('today-signal-signal-0'));
    await tester.tapAt(tester.getCenter(strip) + const Offset(90, 0));
    await tester.pump();
    expect(openAllCalls, 2);
    expect(openSignalCalls, 1);
  });

  testWidgets('Signal dither and watermark use brightness-specific contrast', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        _host(
          TodaySignalBand(items: [_signal(0)]),
          reduceMotion: true,
          brightness: brightness,
        ),
      );
      final field = tester.widget<ThemeV2DitherField>(
        find.byKey(const ValueKey('today-signal-dither-field')),
      );
      final count = tester.widget<Text>(find.text('1'));
      final label = tester.widget<Text>(find.text('Reka 发现'));
      final watermark = tester.widget<TodayRegionWatermark>(
        find.byType(TodayRegionWatermark),
      );
      final dark = brightness == Brightness.dark;

      expect(field.config.opacity, dark ? .32 : .40);
      expect(count.style!.color!.a, closeTo(dark ? .14 : .07, .01));
      expect(label.style!.color!.a, closeTo(dark ? .68 : .44, .01));
      expect(watermark.padding.bottom, 8);
      expect(watermark.labelFirst, isFalse);
    }
  });

  testWidgets('Signal strips use faint type-colored glass', (tester) async {
    const expectedBases = <String, Color>{
      'overdue': Color(0xFFE46A5D),
      'rhythm_gap': Color(0xFF28A9B8),
      'report': Color(0xFF8B6CE8),
      'other': Color(0xFF25B6D6),
    };

    for (final brightness in Brightness.values) {
      for (final entry in expectedBases.entries) {
        final item = _signalOfType(entry.key);
        await tester.pumpWidget(
          _host(
            TodaySignalBand(items: [item]),
            reduceMotion: true,
            brightness: brightness,
          ),
        );

        final glass = tester.widget<ColoredBox>(
          find.byKey(ValueKey('today-signal-glass-${item.id}')),
        );
        expect(glass.color.r, closeTo(entry.value.r, .001));
        expect(glass.color.g, closeTo(entry.value.g, .001));
        expect(glass.color.b, closeTo(entry.value.b, .001));
        expect(glass.color.a, brightness == Brightness.dark ? .10 : .055);
      }
    }
  });
}

TodayRekaItem _signal(int index) => TodayRekaItem(
  id: 'signal-$index',
  type: index.isEven ? 'rhythm_gap' : 'report',
  title: '发现 $index',
  body: '信号内容 $index',
  link: '',
  createdAt: DateTime(2026, 8, 14, 10, index),
);

TodayRekaItem _signalOfType(String type) => TodayRekaItem(
  id: 'signal-$type',
  type: type,
  title: '发现 $type',
  body: '信号内容 $type',
  link: '',
  createdAt: DateTime(2026, 8, 14, 10),
);

Widget _host(
  Widget child, {
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: buildThemeV2Theme(brightness),
  themeAnimationDuration: Duration.zero,
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(411, 860),
      devicePixelRatio: 1,
      disableAnimations: reduceMotion,
    ),
    child: Scaffold(body: SizedBox(width: 375, height: 210, child: child)),
  ),
);
