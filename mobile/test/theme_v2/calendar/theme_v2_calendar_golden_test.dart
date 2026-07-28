import 'dart:io';

import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_mode_state.dart';
import 'package:eureka/theme_v2/calendar/calendar_schedule_grid.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  const surface = ValueKey('calendar-golden-surface');

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
    required Widget child,
    required Brightness brightness,
    Size size = calendarFixtureSize,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      calendarTestHost(
        RepaintBoundary(key: surface, child: child),
        brightness: brightness,
        size: size,
      ),
    );
    await tester.pumpAndSettle();
  }

  ThemeV2CalendarPage page(CalendarMode mode) => ThemeV2CalendarPage(
    controller: CalendarController(
      modeState: CalendarModeState(initialMode: mode),
    ),
    today: DateTime(2026, 7, 3),
    initialData: calendarFixtureData(),
    onOpenDay: (_) {},
    onOpenRecord: (_) {},
    onCreateDraft: (_) async {},
    onOpenDraftEditor: (_) {},
  );

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('flow 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        child: page(CalendarMode.flow),
        brightness: brightness,
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-flow-411-$suffix.png'),
      );
    });

    testWidgets('expanded schedule 411 $suffix', (tester) async {
      final data = calendarFixtureData();
      await pumpGolden(
        tester,
        brightness: brightness,
        child: CalendarScheduleGrid(
          day: DateTime(2026, 7, 3),
          records: data.records,
          skills: data.skills,
          controller: CalendarController(),
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      );
      await tester.tap(find.bySemanticsLabel('展开 2 个待办'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-schedule-expanded-411-$suffix.png'),
      );
    });

    testWidgets('month 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        child: page(CalendarMode.month),
        brightness: brightness,
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-month-411-$suffix.png'),
      );
    });

    testWidgets('year 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        child: page(CalendarMode.year),
        brightness: brightness,
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-year-411-$suffix.png'),
      );
    });
  }

  testWidgets('flow 360 light', (tester) async {
    const narrow = Size(360, 800);
    await pumpGolden(
      tester,
      child: page(CalendarMode.flow),
      brightness: Brightness.light,
      size: narrow,
    );
    await expectLater(
      find.byKey(surface),
      matchesGoldenFile('goldens/calendar-flow-360-light.png'),
    );
  });
}
