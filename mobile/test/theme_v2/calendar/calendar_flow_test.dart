import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:eureka/data_revision.dart' show bumpData;
import 'package:eureka/pages/calendar_page.dart' show calendarHome;
import 'package:eureka/pages/day_flash_view.dart';
import 'package:eureka/pages/session_detail_page.dart';
import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_day_detail.dart';
import 'package:eureka/theme_v2/calendar/calendar_flow_view.dart';
import 'package:eureka/theme_v2/calendar/calendar_mode_state.dart';
import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:eureka/theme_v2/calendar/calendar_month_view.dart';
import 'package:eureka/theme_v2/calendar/calendar_schedule_grid.dart';
import 'package:eureka/theme_v2/calendar/calendar_sticky_date_rail.dart';
import 'package:eureka/theme_v2/calendar/calendar_year_view.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  testWidgets('populated date opens Day Detail on the first tap', (
    tester,
  ) async {
    final controller = CalendarController();
    DateTime? opened;
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: calendarFixtureData(),
          controller: controller,
          today: DateTime(2026, 7, 3),
          onOpenDay: (day) => opened = day,
          onRequestManualRecord: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-date-2026-07-03')));
    await tester.pump();
    expect(controller.selectedDate, DateTime(2026, 7, 3));
    expect(opened, DateTime(2026, 7, 3));
  });

  testWidgets('Flow provides indexed extents so locating today stays lazy', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: calendarFixtureData(),
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onRequestManualRecord: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('calendar-flow-scroll')),
    );
    expect(list.itemExtentBuilder, isNotNull);
  });

  testWidgets('empty date reveals Manual Record before requesting picker', (
    tester,
  ) async {
    final controller = CalendarController();
    DateTime? requested;
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: CalendarData(const [], const {}),
          controller: controller,
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onRequestManualRecord: (day) => requested = day,
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-date-2026-07-03')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('calendar-empty-confirmation-2026-07-03')),
      findsOneWidget,
    );
    expect(requested, isNull);

    await tester.tap(
      find.byKey(const ValueKey('calendar-empty-manual-2026-07-03')),
    );
    expect(requested, DateTime(2026, 7, 3));
  });

  testWidgets(
    'empty date keeps its placeholder and confirmation equally sized',
    (tester) async {
      await tester.pumpWidget(
        calendarTestHost(
          CalendarFlowView(
            data: CalendarData(const [], const {}),
            controller: CalendarController(),
            today: DateTime(2026, 7, 3),
            onOpenDay: (_) {},
            onRequestManualRecord: (_) {},
            onOpenRecord: (_) {},
            onOpenFlash: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final placeholder = find.byKey(
        const ValueKey('calendar-empty-hatch-2026-07-03'),
      );
      expect(placeholder, findsOneWidget);
      final placeholderSize = tester.getSize(placeholder);
      expect(placeholderSize.height, 58);

      final nextDayTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-date-2026-07-04')))
          .dy;
      final followingDayTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-date-2026-07-05')))
          .dy;
      expect(followingDayTop - nextDayTop, 150);

      await tester.tap(find.byKey(const ValueKey('calendar-date-2026-07-03')));
      await tester.pump();

      final confirmation = find.byKey(
        const ValueKey('calendar-empty-confirmation-card-2026-07-03'),
      );
      expect(tester.getSize(confirmation).height, placeholderSize.height);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('empty date paints gray hatching in ${brightness.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        calendarTestHost(
          CalendarFlowView(
            data: CalendarData(const [], const {}),
            controller: CalendarController(),
            today: DateTime(2026, 7, 3),
            onOpenDay: (_) {},
            onRequestManualRecord: (_) {},
            onOpenRecord: (_) {},
            onOpenFlash: (_) {},
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      final hatch = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('calendar-empty-hatch-paint-2026-07-03')),
      );
      expect(hatch.painter, isNotNull);
    });
  }

  testWidgets('record tap uses the injected detail callback', (tester) async {
    String? openedId;
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: calendarFixtureData(),
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onRequestManualRecord: (_) {},
          onOpenRecord: (record) => openedId = record.id,
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-record-event-a')));
    expect(openedId, 'event-a');
  });

  testWidgets('month summary record uses the injected detail callback', (
    tester,
  ) async {
    String? openedId;
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: CalendarController(
            modeState: CalendarModeState(initialMode: CalendarMode.month),
          ),
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (record) => openedId = record.id,
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-record-event-a')));
    expect(openedId, 'event-a');
  });

  testWidgets('flash count control responds to a physical tap', (tester) async {
    var dateTaps = 0;
    var flashTaps = 0;
    await tester.pumpWidget(
      calendarTestHost(
        CalendarStickyDateRail(
          day: DateTime(2026, 7, 3),
          today: DateTime(2026, 7, 3),
          itemCount: 2,
          flashCount: 1,
          onTapDate: () => dateTaps++,
          onOpenFlash: () => flashTaps++,
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('7月3日，1 条闪念，查看闪念'));
    expect(flashTaps, 1);
    expect(dateTaps, 0);
  });

  testWidgets('default Flow Flash opens its session without an intermediate', (
    tester,
  ) async {
    final fixture = calendarFixtureData();
    final data = CalendarData([
      ...fixture.items,
      calendarFixtureItem(
        id: 'flash-a',
        title: '今天想到的事',
        at: DateTime(2026, 7, 3, 11),
        kind: 'input_turn',
        sessionId: 'flash-session-a',
      ),
    ], fixture.skills);
    var openedDays = 0;
    await tester.pumpWidget(
      calendarLegacyRouteTestHost(
        ThemeV2CalendarPage(
          today: DateTime(2026, 7, 3),
          initialData: data,
          onOpenDay: (_) => openedDays++,
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('7月3日，1 条闪念，查看闪念'));
    await tester.pumpAndSettle();

    expect(openedDays, 0);
    expect(find.byType(DayFlashView), findsNothing);
    expect(find.byType(SessionDetailPage), findsOneWidget);
    expect(
      tester
          .widget<SessionDetailPage>(find.byType(SessionDetailPage))
          .sessionId,
      'flash-session-a',
    );
  });

  testWidgets('sticky rail and scroll content are sibling layout regions', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: calendarFixtureData(),
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onRequestManualRecord: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.byKey(const ValueKey('calendar-sticky-date-rail'));
    final content = find.byKey(const ValueKey('calendar-flow-content'));
    expect(rail, findsOneWidget);
    expect(content, findsOneWidget);
    expect(find.descendant(of: rail, matching: content), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-untimed-divider-untimed')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Flow groups time bands and sinks imprecise assets to each reasonable tail',
    (tester) async {
      final day = DateTime(2026, 7, 3);
      final data = CalendarData([
        calendarFixtureItem(
          id: 'morning',
          title: '上午会议',
          at: day.add(const Duration(hours: 9)),
        ),
        calendarFixtureItem(
          id: 'afternoon-soft',
          title: '下午再处理',
          at: day.add(const Duration(hours: 10)),
          kind: 'asset',
          skillName: 'notes',
          period: '下午',
        ),
        calendarFixtureItem(
          id: 'bottom-untimed',
          title: '未说明时间',
          at: day.add(const Duration(hours: 13)),
          kind: 'asset',
          skillName: 'notes',
        ),
        calendarFixtureItem(
          id: 'afternoon-timed',
          title: '下午培训',
          at: day.add(const Duration(hours: 15)),
          kind: 'asset',
          skillName: 'notes',
          hasClockTime: true,
        ),
        calendarFixtureItem(
          id: 'evening',
          title: '晚间复盘',
          at: day.add(const Duration(hours: 20)),
        ),
      ], const {});

      await tester.pumpWidget(
        calendarTestHost(
          CalendarFlowView(
            data: data,
            controller: CalendarController(),
            today: day,
            onOpenDay: (_) {},
            onRequestManualRecord: (_) {},
            onOpenRecord: (_) {},
            onOpenFlash: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('上午 · 1'), findsOneWidget);
      expect(find.text('下午 · 2'), findsOneWidget);
      expect(find.text('晚上 · 1'), findsOneWidget);
      expect(find.text('没说时间 · 1'), findsOneWidget);

      final afternoonTimed = find.text('下午培训');
      final afternoonSoft = find.text('下午再处理');
      final evening = find.text('晚间复盘');
      final bottomUntimed = find.text('未说明时间');
      expect(
        tester.getTopLeft(afternoonTimed).dy,
        lessThan(tester.getTopLeft(afternoonSoft).dy),
      );
      expect(
        tester.getTopLeft(afternoonSoft).dy,
        lessThan(tester.getTopLeft(evening).dy),
      );
      expect(
        tester.getTopLeft(evening).dy,
        lessThan(tester.getTopLeft(bottomUntimed).dy),
      );
      expect(
        find.byKey(const ValueKey('calendar-untimed-divider-afternoon-soft')),
        findsOneWidget,
      );
    },
  );

  testWidgets('rich Flow days grow to keep their final record visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: calendarHandoffOverviewData(),
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onRequestManualRecord: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final day = find.byKey(const ValueKey('calendar-day-content-2026-07-03'));
    final finalRecord = find.byKey(
      const ValueKey('calendar-record-handoff-note'),
    );
    expect(finalRecord, findsOneWidget);
    expect(
      tester.getBottomRight(finalRecord).dy,
      lessThanOrEqualTo(tester.getBottomRight(day).dy),
    );
  });

  testWidgets('refresh preserves the visible Flow day and intra-day offset', (
    tester,
  ) async {
    final initial = calendarFixtureData();
    final data = ValueNotifier(initial);
    addTearDown(data.dispose);
    await tester.pumpWidget(
      calendarTestHost(
        ValueListenableBuilder<CalendarData>(
          valueListenable: data,
          builder: (_, value, _) => CalendarFlowView(
            data: value,
            controller: CalendarController(),
            today: DateTime(2026, 7, 3),
            onOpenDay: (_) {},
            onRequestManualRecord: (_) {},
            onOpenRecord: (_) {},
            onOpenFlash: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var list = tester.widget<ListView>(
      find.byKey(const ValueKey('calendar-flow-scroll')),
    );
    list.controller!.jumpTo(list.controller!.offset + 100);
    await tester.pump();
    final beforeRefresh = list.controller!.offset;
    final visibleDay = find.byKey(
      const ValueKey('calendar-day-content-2026-07-03'),
    );
    final beforeDayTop = tester.getTopLeft(visibleDay).dy;

    data.value = CalendarData([
      ...initial.items,
      for (var index = 0; index < 4; index++)
        calendarFixtureItem(
          id: 'historic-$index',
          at: DateTime(2026, 7, 2, 9 + index),
        ),
    ], initial.skills);
    await tester.pump();
    await tester.pump();

    list = tester.widget<ListView>(
      find.byKey(const ValueKey('calendar-flow-scroll')),
    );
    expect(list.controller!.offset, greaterThan(beforeRefresh));
    expect(tester.getTopLeft(visibleDay).dy, closeTo(beforeDayTop, 0.01));
    expect(find.bySemanticsLabel('7月3日，打开日期'), findsOneWidget);
  });

  testWidgets('non-sticky Flow dates keep Flash as an independent action', (
    tester,
  ) async {
    DateTime? opened;
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: calendarHandoffOverviewData(),
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onRequestManualRecord: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (day) => opened = day,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('calendar-flow-scroll')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    final nextDayFlash = find.bySemanticsLabel('7月4日，2 条闪念，查看闪念');
    expect(nextDayFlash, findsOneWidget);
    await tester.tap(nextDayFlash);
    expect(opened, DateTime(2026, 7, 4));
  });

  testWidgets(
    'watermark is absent at rest and follows center date only while moving',
    (tester) async {
      await tester.pumpWidget(
        calendarTestHost(
          CalendarFlowView(
            data: CalendarData(const [], const {}),
            controller: CalendarController(),
            today: DateTime(2026, 7, 3),
            onOpenDay: (_) {},
            onRequestManualRecord: (_) {},
            onOpenRecord: (_) {},
            onOpenFlash: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-flow-watermark')),
        findsNothing,
      );

      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('calendar-flow-scroll')),
      );
      list.controller!.jumpTo(list.controller!.offset + 8 * 180);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('calendar-flow-watermark')),
        findsNothing,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('calendar-flow-scroll'))),
      );
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      final watermark = tester.widget<Text>(
        find.byKey(const ValueKey('calendar-flow-watermark')),
      );
      expect(watermark.data, contains('WEEK'));
      expect(watermark.data, isNot(contains('+')));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-flow-watermark')),
        findsNothing,
      );
    },
  );

  testWidgets('Return to Today appears at seven days and centers Today', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 3);
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: CalendarData(const [], const {}),
          controller: CalendarController(),
          today: today,
          onOpenDay: (_) {},
          onRequestManualRecord: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byKey(const ValueKey('calendar-flow-scroll'));
    final list = tester.widget<ListView>(scrollFinder);
    final initialOffset = list.controller!.offset;
    final halfViewport = list.controller!.position.viewportDimension / 2;
    final emptyDayExtent =
        tester
            .getTopLeft(find.byKey(const ValueKey('calendar-date-2026-07-05')))
            .dy -
        tester
            .getTopLeft(find.byKey(const ValueKey('calendar-date-2026-07-04')))
            .dy;
    list.controller!.jumpTo(
      initialOffset + 6 * emptyDayExtent + emptyDayExtent / 2 - halfViewport,
    );
    await tester.pump();
    expect(find.bySemanticsLabel('回到今天'), findsNothing);

    list.controller!.jumpTo(
      initialOffset + 7 * emptyDayExtent + emptyDayExtent / 2 - halfViewport,
    );
    await tester.pump();

    final returnToday = find.bySemanticsLabel('回到今天');
    expect(returnToday, findsOneWidget);
    await tester.tap(returnToday);
    await tester.pumpAndSettle();

    expect(returnToday, findsNothing);
    final viewportCenter = tester.getRect(scrollFinder).center.dy;
    final todayContent = tester.getRect(
      find.byKey(const ValueKey('calendar-day-content-2026-07-03')),
    );
    expect(
      viewportCenter,
      closeTo(todayContent.top - 76 + emptyDayExtent / 2, 0.01),
    );
  });

  testWidgets('next day pushes the sticky rail at the day boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        CalendarFlowView(
          data: calendarFixtureData(),
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onRequestManualRecord: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.byKey(const ValueKey('calendar-sticky-date-rail'));
    final initialTop = tester.getTopLeft(rail).dy;
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('calendar-flow-scroll')),
    );
    list.controller!.jumpTo(list.controller!.offset + 420);
    await tester.pump();

    expect(tester.getTopLeft(rail).dy, lessThan(initialTop));
  });

  testWidgets('horizontal swipe moves through one shared scale state', (
    tester,
  ) async {
    final controller = CalendarController();
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: controller,
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('calendar-mode-pages')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.mode, CalendarMode.month);
    expect(find.byKey(const ValueKey('calendar-month-view')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('calendar-mode-pages')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.mode, CalendarMode.year);
    expect(find.byKey(const ValueKey('calendar-year-view')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('calendar-mode-pages')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.mode, CalendarMode.flow);
    expect(find.byKey(const ValueKey('calendar-flow-content')), findsOneWidget);
  });

  testWidgets('overview scales stay headerless with a small top gap', (
    tester,
  ) async {
    final controller = CalendarController(
      modeState: CalendarModeState(initialMode: CalendarMode.month),
    );
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: controller,
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CALENDAR / MONTH'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-month-top-gap')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('calendar-mode-pages')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('CALENDAR / YEAR'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-year-top-gap')), findsOneWidget);
  });

  testWidgets('horizontal drag reveals the target scale in an edge droplet', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
        disableAnimations: false,
      ),
    );
    await tester.pumpAndSettle();

    final pages = find.byKey(const ValueKey('calendar-mode-pages'));
    final gesture = await tester.startGesture(tester.getCenter(pages));
    await gesture.moveBy(const Offset(-8, 0));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('calendar-scale-drag-indicator')),
      findsNothing,
    );

    await gesture.moveBy(const Offset(-42, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump();

    final indicator = find.byKey(
      const ValueKey('calendar-scale-drag-indicator'),
    );
    expect(indicator, findsOneWidget);
    expect(
      find.descendant(of: indicator, matching: find.text('月览')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-scale-drag-droplet')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(indicator, findsNothing);
  });

  testWidgets(
    'scale droplet starts at gesture Y and follows vertical motion with damping',
    (tester) async {
      await tester.pumpWidget(
        calendarTestHost(
          ThemeV2CalendarPage(
            controller: CalendarController(),
            today: DateTime(2026, 7, 3),
            initialData: calendarFixtureData(),
            onOpenDay: (_) {},
            onOpenRecord: (_) {},
            onCreateDraft: (_) async {},
            onOpenDraftEditor: (_) {},
          ),
          disableAnimations: false,
        ),
      );
      await tester.pumpAndSettle();

      final pages = find.byKey(const ValueKey('calendar-mode-pages'));
      final pageRect = tester.getRect(pages);
      final origin = Offset(pageRect.center.dx, pageRect.top + 140);
      final indicator = find.byKey(
        const ValueKey('calendar-scale-drag-indicator'),
      );
      final gesture = await tester.startGesture(origin);

      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getCenter(indicator).dy, closeTo(origin.dy, 2));

      final beforeFollow = tester.getCenter(indicator).dy;
      await gesture.moveBy(const Offset(-4, 50));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final afterFollow = tester.getCenter(indicator).dy;
      expect(afterFollow - beforeFollow, closeTo(30, 3));

      await gesture.cancel();
      await tester.pumpAndSettle();

      final jitterGesture = await tester.startGesture(origin);
      await jitterGesture.moveBy(const Offset(-60, 2));
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getCenter(indicator).dy, closeTo(origin.dy, 1));

      await jitterGesture.cancel();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('scale droplet clamps inside the Calendar viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
        disableAnimations: false,
      ),
    );
    await tester.pumpAndSettle();

    final pages = find.byKey(const ValueKey('calendar-mode-pages'));
    final pageRect = tester.getRect(pages);
    final indicator = find.byKey(
      const ValueKey('calendar-scale-drag-indicator'),
    );

    final topGesture = await tester.startGesture(
      Offset(pageRect.center.dx, pageRect.top + 2),
    );
    await topGesture.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getCenter(indicator).dy, closeTo(pageRect.top + 64.5, 2));

    await topGesture.cancel();
    await tester.pumpAndSettle();

    final bottomGesture = await tester.startGesture(
      Offset(pageRect.center.dx, pageRect.bottom - 2),
    );
    await bottomGesture.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getCenter(indicator).dy, closeTo(pageRect.bottom - 64.5, 2));

    await bottomGesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion keeps the edge label without droplet morphing', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pages = find.byKey(const ValueKey('calendar-mode-pages'));
    final gesture = await tester.startGesture(tester.getCenter(pages));
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump();

    final indicator = find.byKey(
      const ValueKey('calendar-scale-drag-indicator'),
    );
    expect(indicator, findsOneWidget);
    expect(
      find.descendant(of: indicator, matching: find.text('月览')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-scale-drag-droplet')),
      findsNothing,
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a completed scale switch briefly confirms the new view', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: CalendarController(),
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
        disableAnimations: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('calendar-mode-pages')),
      const Offset(-350, 0),
    );
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final confirmation = find.byKey(
      const ValueKey('calendar-scale-confirmation'),
    );
    expect(confirmation, findsOneWidget);
    expect(
      find.descendant(of: confirmation, matching: find.text('月览')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(confirmation, findsNothing);
  });

  testWidgets('vertical Flow intent does not trigger a scale switch', (
    tester,
  ) async {
    final controller = CalendarController();
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: controller,
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('calendar-flow-scroll')),
      const Offset(12, -350),
    );
    await tester.pumpAndSettle();

    expect(controller.mode, CalendarMode.flow);
    expect(find.byKey(const ValueKey('calendar-flow-content')), findsOneWidget);
  });

  testWidgets('calendar reselect returns to Flow and today', (tester) async {
    final controller = CalendarController(
      modeState: CalendarModeState(initialMode: CalendarMode.year),
      selectedDate: DateTime(2026, 8, 4),
    );
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: controller,
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    calendarHome.value++;
    await tester.pumpAndSettle();

    expect(controller.mode, CalendarMode.flow);
    expect(controller.selectedDate, DateTime(2026, 7, 3));
    expect(find.byKey(const ValueKey('calendar-flow-watermark')), findsNothing);
    expect(find.bySemanticsLabel('回到今天'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-date-2026-07-03')),
      findsOneWidget,
    );
  });

  testWidgets('first populated date tap opens Theme V2 Day Detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final today = find.byKey(const ValueKey('calendar-date-2026-07-03'));
    await tester.tap(today);
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDayDetail), findsOneWidget);
    expect(find.byType(CalendarScheduleGrid), findsNothing);
    expect(find.text('7 项记录'), findsOneWidget);
  });

  testWidgets('month and year derive responsive cells at 360px', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: CalendarController(
            modeState: CalendarModeState(initialMode: CalendarMode.month),
          ),
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
        size: const Size(360, 800),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-month-2026-06-29')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-month-2026-08-09')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey('calendar-mode-pages')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-year-2026-12')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('year view tracks an updated focus year and month', (
    tester,
  ) async {
    final focus = ValueNotifier(DateTime(2026, 7));
    addTearDown(focus.dispose);

    Widget view() => calendarTestHost(
      ValueListenableBuilder<DateTime>(
        valueListenable: focus,
        builder: (_, value, _) => CalendarYearView(
          focusMonth: value,
          data: calendarFixtureData(),
          today: DateTime(2026, 7, 3),
          onSelectMonth: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(view());
    expect(find.byKey(const ValueKey('calendar-year-2026-7')), findsOneWidget);

    focus.value = DateTime(2027, 2);
    await tester.pump();
    expect(find.byKey(const ValueKey('calendar-year-2027-2')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('calendar-year-2027-2')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('Month and Year expose real progressive activity summaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        CalendarYearView(
          focusMonth: DateTime(2026, 7),
          data: calendarFixtureData(),
          today: DateTime(2026, 7, 3),
          onSelectMonth: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-year-summary')), findsOneWidget);
    expect(find.text('7月概览'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-year-summary-records')),
        matching: find.text('8 条'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      calendarTestHost(
        CalendarMonthView(
          month: DateTime(2026, 7),
          data: calendarFixtureData(),
          controller: CalendarController(selectedDate: DateTime(2026, 7, 3)),
          today: DateTime(2026, 7, 3),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-month-activity-2026-07-03')),
      findsOneWidget,
    );
  });

  testWidgets(
    'month selection updates real summary before opening Day Detail',
    (tester) async {
      DateTime? opened;
      await tester.pumpWidget(
        calendarTestHost(
          ThemeV2CalendarPage(
            controller: CalendarController(
              modeState: CalendarModeState(initialMode: CalendarMode.month),
            ),
            today: DateTime(2026, 7, 3),
            initialData: calendarFixtureData(),
            onOpenDay: (day) => opened = day,
            onOpenRecord: (_) {},
            onCreateDraft: (_) async {},
            onOpenDraftEditor: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final july4 = find.byKey(const ValueKey('calendar-month-2026-07-04'));
      await tester.tap(july4);
      await tester.pump();

      expect(find.text('周末训练'), findsOneWidget);
      expect(opened, isNull);
      expect(find.textContaining('再次点击'), findsNothing);

      await tester.tap(july4);
      await tester.pump();
      expect(opened, DateTime(2026, 7, 4));
    },
  );

  testWidgets('year month selection changes focus month and scale', (
    tester,
  ) async {
    final controller = CalendarController(
      modeState: CalendarModeState(initialMode: CalendarMode.year),
    );
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: controller,
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-year-2026-12')));
    await tester.pumpAndSettle();

    expect(find.text('12月概览'), findsOneWidget);
    expect(controller.mode, CalendarMode.year);
    await tester.tap(find.text('查看月度 ›'));
    await tester.pumpAndSettle();

    expect(controller.mode, CalendarMode.month);
    expect(find.text('2026年12月'), findsOneWidget);
  });

  testWidgets('refresh keeps Year, selected date, and mounted scale pages', (
    tester,
  ) async {
    final refreshGate = Completer<CalendarData>();
    var calls = 0;
    Future<CalendarData> load() {
      calls++;
      if (calls == 1) return Future.value(calendarFixtureData());
      return refreshGate.future;
    }

    final controller = CalendarController(
      modeState: CalendarModeState(initialMode: CalendarMode.year),
      selectedDate: DateTime(2026, 7, 4),
    );
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: controller,
          today: DateTime(2026, 7, 3),
          dataLoader: load,
        ),
      ),
    );
    await tester.pumpAndSettle();
    bumpData();
    await tester.pump();

    expect(controller.mode, CalendarMode.year);
    expect(controller.selectedDate, DateTime(2026, 7, 4));
    expect(find.byKey(const ValueKey('calendar-mode-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-year-view')), findsOneWidget);

    refreshGate.complete(calendarFixtureData());
    await tester.pumpAndSettle();
  });

  testWidgets('Android back unwinds Schedule then Day Detail locally', (
    tester,
  ) async {
    final controller = CalendarController()
      ..openDay(DateTime(2026, 7, 3))
      ..openSchedule();
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          controller: controller,
          today: DateTime(2026, 7, 3),
          initialData: calendarFixtureData(),
          onOpenRecord: (_) {},
          onCreateDraft: (_) async {},
          onOpenDraftEditor: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScheduleGrid), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.surface, CalendarSurface.dayDetail);
    expect(find.byType(CalendarDayDetail), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.surface, CalendarSurface.overview);
    expect(find.byKey(const ValueKey('calendar-flow-content')), findsOneWidget);
  });

  testWidgets('initial loading keeps Calendar scales mounted', (tester) async {
    final gate = Completer<CalendarData>();
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          today: DateTime(2026, 7, 3),
          dataLoader: () => gate.future,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('calendar-mode-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-flow-content')), findsOneWidget);
    expect(find.text('正在加载日历'), findsOneWidget);

    gate.complete(calendarFixtureData());
    await tester.pumpAndSettle();
  });

  testWidgets('an empty Calendar remains interactive without global teaching', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          today: DateTime(2026, 7, 3),
          initialData: CalendarData(const [], const {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-flow-content')), findsOneWidget);
    expect(find.text('还没有日历记录'), findsNothing);
    expect(find.text('选择日期即可创建第一条日程。'), findsNothing);
  });

  testWidgets('loading, error, retry, and empty retain calendar structure', (
    tester,
  ) async {
    final gate = Completer<CalendarData>();
    var calls = 0;
    Future<CalendarData> load() {
      calls++;
      if (calls == 1) return gate.future;
      if (calls == 2) return Future.error(StateError('offline'));
      return Future.value(CalendarData(const [], const {}));
    }

    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(today: DateTime(2026, 7, 3), dataLoader: load),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('calendar-mode-pages')), findsOneWidget);
    expect(find.text('正在加载日历'), findsOneWidget);

    gate.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('日历加载失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-mode-pages')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('重试'));
    await tester.pumpAndSettle();
    expect(find.text('日历加载失败'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有日历记录'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-mode-pages')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-date-2026-07-03')),
      findsOneWidget,
    );
  });
}
