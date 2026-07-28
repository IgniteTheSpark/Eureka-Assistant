import 'package:eureka/theme_v2/calendar/calendar_day_detail.dart';
import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  Widget detail(
    CalendarDayData dayData, {
    VoidCallback? onOpenFlash,
    VoidCallback? onManualRecord,
    VoidCallback? onOpenSchedule,
  }) {
    return calendarTestHost(
      CalendarDayDetail(
        dayData: dayData,
        skills: const {},
        onBack: () {},
        onOpenSchedule: onOpenSchedule ?? () {},
        onOpenFlash: onOpenFlash ?? () {},
        onManualRecord: onManualRecord ?? () {},
        onOpenRecord: (_) {},
      ),
    );
  }

  testWidgets('Asset empty keeps Flash and independent actions', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 3);
    final data = CalendarData([
      for (var index = 0; index < 5; index++)
        calendarFixtureItem(
          id: 'flash-$index',
          at: day.add(Duration(minutes: index)),
          kind: 'input_turn',
        ),
    ], const {});

    await tester.pumpWidget(detail(data.day(day)));

    expect(find.text('03'), findsOneWidget);
    expect(find.text('0 项记录'), findsOneWidget);
    expect(find.text('闪念 5'), findsOneWidget);
    expect(find.text('今天还没有记录'), findsOneWidget);
    expect(find.text('手动记录'), findsNWidgets(2));
    expect(find.text('日程'), findsOneWidget);
    expect(find.textContaining('从闪念'), findsNothing);
  });

  testWidgets('zero Flash remains visible and actionable', (tester) async {
    final day = DateTime(2026, 7, 3);
    var opened = false;

    await tester.pumpWidget(
      detail(
        CalendarData(const [], const {}).day(day),
        onOpenFlash: () => opened = true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('7月3日，0 条闪念，查看闪念'));
    expect(opened, isTrue);
    expect(find.text('闪念 0'), findsOneWidget);
  });

  testWidgets('manual and Schedule actions expose 44px targets', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 3);
    var manual = 0;
    var schedule = 0;

    await tester.pumpWidget(
      detail(
        CalendarData(const [], const {}).day(day),
        onManualRecord: () => manual++,
        onOpenSchedule: () => schedule++,
      ),
    );

    final manualAction = find.bySemanticsLabel('7月3日，手动记录');
    final scheduleAction = find.bySemanticsLabel('7月3日，查看日程');
    expect(tester.getRect(manualAction).height, greaterThanOrEqualTo(44));
    expect(tester.getRect(scheduleAction).height, greaterThanOrEqualTo(44));

    await tester.tap(manualAction);
    await tester.tap(scheduleAction);
    expect(manual, 1);
    expect(schedule, 1);
  });

  testWidgets('renders only real time bands in effective-time order', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 3);
    final data = CalendarData([
      calendarFixtureItem(
        id: 'untimed',
        title: '整理项目复盘',
        at: day.add(const Duration(hours: 16)),
        kind: 'asset',
        skillName: 'notes',
      ),
      calendarFixtureItem(
        id: 'afternoon',
        title: '培训',
        at: day.add(const Duration(hours: 15)),
      ),
      calendarFixtureItem(
        id: 'morning-later',
        title: '客户拜访',
        at: day.add(const Duration(hours: 10)),
      ),
      calendarFixtureItem(
        id: 'morning-first',
        title: '线上复盘会',
        at: day.add(const Duration(hours: 9)),
      ),
    ], const {});

    await tester.pumpWidget(detail(data.day(day)));

    expect(find.text('上午 · 2'), findsOneWidget);
    expect(find.text('下午 · 1'), findsOneWidget);
    expect(find.text('晚上'), findsNothing);
    expect(find.text('没说时间 · 1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('线上复盘会')).dy,
      lessThan(tester.getTopLeft(find.text('客户拜访')).dy),
    );
  });
}
