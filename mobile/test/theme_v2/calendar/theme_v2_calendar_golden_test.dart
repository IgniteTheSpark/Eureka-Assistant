import 'dart:io';
import 'dart:ui';

import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_manual_record_picker.dart';
import 'package:eureka/theme_v2/calendar/calendar_mode_state.dart';
import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  const surface = ValueKey('calendar-golden-surface');
  final today = DateTime(2026, 7, 3);

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

  Widget calendarPage({
    required CalendarController controller,
    required CalendarData data,
  }) {
    return ThemeV2CalendarPage(
      controller: controller,
      today: today,
      initialData: data,
      onOpenRecord: (_) {},
      onCreateDraft: (_) async {},
      onOpenDraftEditor: (_) {},
    );
  }

  Widget withCalendarDock(Widget child, {bool showDock = true}) {
    return ThemeV2PageScaffold(
      showDock: showDock,
      body: child,
      topNav: ThemeV2GlobalTopNav(
        deviceStatus: const DeviceStatusSummary.disconnected(),
        onDevicePressed: () {},
        onNotificationsPressed: () {},
      ),
      dock: ThemeV2FloatingDock(
        selectedIndex: 1,
        onDestinationSelected: (_) {},
      ),
    );
  }

  Widget manualPickerState(Brightness brightness) {
    final base = withCalendarDock(
      calendarPage(
        controller: CalendarController(),
        data: calendarHandoffOverviewData(),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: base),
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(
                color: Colors.black.withValues(
                  alpha: brightness == Brightness.dark ? 0.38 : 0.28,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: CalendarManualRecordPicker(
            effectiveDate: today,
            loader: () async => const CalendarSkillCatalog(
              options: [
                CalendarSkillOption.event(),
                CalendarSkillOption.asset(
                  name: 'todo',
                  displayName: '待办',
                  icon: '📋',
                  userSkillId: 'todo',
                ),
                CalendarSkillOption.asset(
                  name: 'note',
                  displayName: '笔记',
                  icon: '📝',
                  userSkillId: 'note',
                ),
                CalendarSkillOption.contact(
                  displayName: '联系人',
                  icon: '👤',
                  userSkillId: 'contact',
                ),
                CalendarSkillOption.asset(
                  name: 'running',
                  displayName: '跑步训练',
                  icon: '🏃',
                  userSkillId: 'running',
                ),
                CalendarSkillOption.asset(
                  name: 'coffee',
                  displayName: '咖啡记录',
                  icon: '☕',
                  userSkillId: 'coffee',
                ),
              ],
              recentNames: ['coffee', 'running', 'note', 'todo'],
            ),
            onSelected: (_) {},
            onClose: () {},
          ),
        ),
      ],
    );
  }

  Future<void> pumpGolden(
    WidgetTester tester, {
    required Widget child,
    required Brightness brightness,
    bool disableAnimations = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = calendarFixtureSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      calendarTestHost(
        RepaintBoundary(key: surface, child: child),
        brightness: brightness,
        disableAnimations: disableAnimations,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<TestGesture> revealDropletAt(
    WidgetTester tester,
    Finder pages, {
    required double dyFromTop,
  }) async {
    final rect = tester.getRect(pages);
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.top + dyFromTop),
    );
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump();
    return gesture;
  }

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('Flow resting 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(),
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-flow-resting-411-$suffix.png'),
      );
    });

    testWidgets('Flow drag toward Month at upper origin 411 $suffix', (
      tester,
    ) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        disableAnimations: false,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(),
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      final pages = find.byKey(const ValueKey('calendar-mode-pages'));
      final gesture = await revealDropletAt(tester, pages, dyFromTop: 150);

      expect(
        find.byKey(const ValueKey('calendar-scale-drag-droplet')),
        findsOneWidget,
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-flow-drag-month-411-$suffix.png'),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Flow drag toward Month at lower origin 411 $suffix', (
      tester,
    ) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        disableAnimations: false,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(),
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      final pages = find.byKey(const ValueKey('calendar-mode-pages'));
      final gesture = await revealDropletAt(
        tester,
        pages,
        dyFromTop: tester.getSize(pages).height - 150,
      );

      expect(
        find.byKey(const ValueKey('calendar-scale-drag-droplet')),
        findsOneWidget,
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile(
          'goldens/calendar-flow-drag-month-lower-411-$suffix.png',
        ),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Flow empty date 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(),
            data: CalendarData(const [], const {}),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('calendar-empty-hatch-2026-07-03')),
        findsOneWidget,
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-flow-empty-411-$suffix.png'),
      );
    });

    testWidgets('Flow sticky threshold 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(),
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      final scroll = tester.widget<ListView>(
        find.byKey(const ValueKey('calendar-flow-scroll')),
      );
      scroll.controller!.jumpTo(scroll.controller!.offset + 112);
      await tester.pump();
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-flow-threshold-411-$suffix.png'),
      );
    });

    testWidgets('Flow far scroll 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(),
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      final scrollFinder = find.byKey(const ValueKey('calendar-flow-scroll'));
      final scroll = tester.widget<ListView>(scrollFinder);
      scroll.controller!.jumpTo(scroll.controller!.offset + 16 * 180);
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(scrollFinder));
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();

      expect(find.text('2 WEEKS LATER'), findsOneWidget);
      expect(find.bySemanticsLabel('回到今天'), findsOneWidget);
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-flow-far-scroll-411-$suffix.png'),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Month 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(
              modeState: CalendarModeState(initialMode: CalendarMode.month),
              selectedDate: today,
            ),
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-month-411-$suffix.png'),
      );
    });

    testWidgets('Year 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: CalendarController(
              modeState: CalendarModeState(initialMode: CalendarMode.year),
            ),
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-year-411-$suffix.png'),
      );
    });

    testWidgets('Day populated 411 $suffix', (tester) async {
      final controller = CalendarController()..openDay(today);
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: controller,
            data: calendarHandoffOverviewData(),
          ),
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-day-populated-411-$suffix.png'),
      );
    });

    testWidgets('Day Asset empty 411 $suffix', (tester) async {
      final controller = CalendarController()..openDay(today);
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: controller,
            data: calendarHandoffAssetEmptyData(),
          ),
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-day-asset-empty-411-$suffix.png'),
      );
    });

    testWidgets('Schedule default 411 $suffix', (tester) async {
      final controller = CalendarController()
        ..openDay(today)
        ..openSchedule();
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: controller,
            data: calendarHandoffScheduleData(),
          ),
          showDock: false,
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-schedule-default-411-$suffix.png'),
      );
    });

    testWidgets('Schedule Todo expanded 411 $suffix', (tester) async {
      final controller = CalendarController()
        ..openDay(today)
        ..openSchedule();
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: controller,
            data: calendarHandoffScheduleData(),
          ),
          showDock: false,
        ),
      );
      await tester.tap(find.bySemanticsLabel('展开 3 个待办'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-schedule-expanded-411-$suffix.png'),
      );
    });

    testWidgets('Schedule inline draft 411 $suffix', (tester) async {
      final controller = CalendarController()
        ..openDay(today)
        ..openSchedule()
        ..tapEmptyTime(DateTime(2026, 7, 3, 16));
      await pumpGolden(
        tester,
        brightness: brightness,
        child: withCalendarDock(
          calendarPage(
            controller: controller,
            data: calendarHandoffScheduleData(),
          ),
          showDock: false,
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('calendar-inline-draft')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-schedule-draft-411-$suffix.png'),
      );
    });

    testWidgets('Manual Record Picker 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        child: manualPickerState(brightness),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-manual-picker-411-$suffix.png'),
      );
    });
  }
}
