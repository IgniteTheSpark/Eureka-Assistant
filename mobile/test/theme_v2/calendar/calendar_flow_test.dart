import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:eureka/data_revision.dart' show bumpData;
import 'package:eureka/pages/calendar_page.dart' show calendarHome;
import 'package:eureka/pages/day_flash_view.dart';
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

  testWidgets('default flash callback opens the existing day flash route', (
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
    expect(find.byType(DayFlashView), findsOneWidget);
    expect(find.text('7月3日 · 1 条闪念'), findsOneWidget);
    expect(find.text('今天想到的事'), findsOneWidget);
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
    expect(list.controller!.offset, closeTo(beforeRefresh + 124, 0.01));
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

    final nextDayFlash = find.bySemanticsLabel('7月4日，2 条闪念，查看闪念');
    expect(nextDayFlash, findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('calendar-flow-scroll')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(nextDayFlash);
    expect(opened, DateTime(2026, 7, 4));
  });

  testWidgets('watermark follows progressive vertical scroll', (tester) async {
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
    expect(find.text('TODAY'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('calendar-flow-scroll')),
      const Offset(0, -650),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 DAY LATER'), findsWidgets);
    expect(find.text('+1 DAY'), findsNothing);
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
    list.controller!.jumpTo(list.controller!.offset + 360);
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
    expect(find.text('TODAY'), findsOneWidget);
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
