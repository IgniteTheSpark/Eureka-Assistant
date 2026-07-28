import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_inline_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  testWidgets('cancel clears an inline draft through the visible action', (
    tester,
  ) async {
    final controller = CalendarController()
      ..tapEmptyTime(DateTime(2026, 7, 3, 12));
    await tester.pumpWidget(
      calendarTestHost(
        CalendarInlineDraftView(
          controller: controller,
          onCreate: (_) async {},
          onOpenEditor: (_) {},
          onChanged: () {},
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('取消临时日程'));
    await tester.pump();
    expect(controller.inlineDraft, isNull);
  });

  testWidgets('failed confirm retains draft and exposes retry', (tester) async {
    final controller = CalendarController()
      ..tapEmptyTime(DateTime(2026, 7, 3, 12));
    var calls = 0;
    await tester.pumpWidget(
      calendarTestHost(
        CalendarInlineDraftView(
          controller: controller,
          onCreate: (_) async {
            calls++;
            throw StateError('offline');
          },
          onOpenEditor: (_) {},
          onChanged: () {},
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('确认创建临时日程'));
    await tester.pumpAndSettle();
    expect(controller.inlineDraft, isNotNull);
    expect(find.text('创建失败，请重试'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('重试创建临时日程'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('successful creation sends a subsequent open to full editor', (
    tester,
  ) async {
    final controller = CalendarController()
      ..tapEmptyTime(DateTime(2026, 7, 3, 12));
    var opened = 0;
    await tester.pumpWidget(
      calendarTestHost(
        CalendarInlineDraftView(
          controller: controller,
          onCreate: (_) async {},
          onOpenEditor: (_) => opened++,
          onChanged: () {},
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('确认创建临时日程'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('打开完整日程编辑器'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('every inline draft action exposes a 44px semantic target', (
    tester,
  ) async {
    final controller = CalendarController()
      ..tapEmptyTime(DateTime(2026, 7, 3, 12));
    await tester.pumpWidget(
      calendarTestHost(
        CalendarInlineDraftView(
          controller: controller,
          onCreate: (_) async {},
          onOpenEditor: (_) {},
          onChanged: () {},
        ),
      ),
    );

    for (final label in ['取消临时日程', '确认创建临时日程']) {
      final rect = tester.getRect(find.bySemanticsLabel(label));
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
  });
}
