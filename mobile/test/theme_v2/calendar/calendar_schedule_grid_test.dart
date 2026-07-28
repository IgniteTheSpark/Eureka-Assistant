import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:eureka/theme_v2/calendar/calendar_schedule_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  Widget grid({
    CalendarController? controller,
    ValueChanged<CalendarRecord>? onOpenRecord,
    CalendarDraftMutation? onCreateDraft,
    ValueChanged<CalendarInlineDraft>? onOpenDraftEditor,
  }) {
    final data = calendarFixtureData();
    return calendarTestHost(
      CalendarScheduleGrid(
        day: DateTime(2026, 7, 3),
        records: data.records,
        skills: data.skills,
        controller: controller ?? CalendarController(),
        onOpenRecord: onOpenRecord ?? (_) {},
        onCreateDraft: onCreateDraft ?? (_) async {},
        onOpenDraftEditor: onOpenDraftEditor ?? (_) {},
      ),
    );
  }

  testWidgets('intersecting timed records use stable parallel columns', (
    tester,
  ) async {
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    final a = tester.getRect(
      find.byKey(const ValueKey('calendar-grid-record-event-a')),
    );
    final b = tester.getRect(
      find.byKey(const ValueKey('calendar-grid-record-event-b')),
    );
    expect(a.left, isNot(b.left));
    expect(a.width, closeTo(b.width, 0.01));
  });

  testWidgets('same-minute todos expand individually and push later content', (
    tester,
  ) async {
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();
    final laterFinder = find.byKey(
      const ValueKey('calendar-grid-record-later-event'),
    );
    final collapsedTop = tester.getTopLeft(laterFinder).dy;

    expect(find.text('2 个待办'), findsOneWidget);
    expect(find.text('回访客户'), findsNothing);
    await tester.tap(find.bySemanticsLabel('展开 2 个待办'));
    await tester.pumpAndSettle();

    expect(find.text('回访客户'), findsOneWidget);
    expect(find.text('整理纪要'), findsOneWidget);
    expect(tester.getTopLeft(laterFinder).dy, greaterThan(collapsedTop));
  });

  testWidgets(
    'collapsed todo band reserves 15 minutes with a 44px semantic target',
    (tester) async {
      await tester.pumpWidget(grid());
      await tester.pumpAndSettle();

      final band = find.bySemanticsLabel('展开 2 个待办');
      final adjacent = find.byKey(
        const ValueKey('calendar-grid-record-adjacent-event'),
      );
      final bandRect = tester.getRect(band);
      final adjacentRect = tester.getRect(adjacent);

      expect(bandRect.height, greaterThanOrEqualTo(44));
      expect(adjacentRect.left, closeTo(bandRect.left, 0.01));
      expect(adjacentRect.width, closeTo(bandRect.width, 0.01));
    },
  );

  testWidgets('short timed blocks keep a separate 44px semantic target', (
    tester,
  ) async {
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    final visual = tester.getRect(
      find.byKey(const ValueKey('calendar-grid-record-adjacent-event')),
    );
    final semantic = tester.getRect(find.bySemanticsLabel('十五分钟后开始'));
    expect(visual.height, closeTo(16, 0.01));
    expect(semantic.height, greaterThanOrEqualTo(44));
  });

  testWidgets('schedule renders the complete 00:00 to 24:00 day grid', (
    tester,
  ) async {
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-empty-slot-2026-07-03-0000')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-empty-slot-2026-07-03-2300')),
      findsOneWidget,
    );
  });

  testWidgets('empty slot creates a 30-minute inline draft', (tester) async {
    final controller = CalendarController();
    await tester.pumpWidget(grid(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('calendar-empty-slot-2026-07-03-1200')),
    );
    await tester.pump();

    expect(controller.inlineDraft?.startAt, DateTime(2026, 7, 3, 12));
    expect(controller.inlineDraft?.endAt, DateTime(2026, 7, 3, 12, 30));
    expect(find.byKey(const ValueKey('calendar-inline-draft')), findsOneWidget);
  });

  testWidgets('created inline draft remains available for full editing', (
    tester,
  ) async {
    final controller = CalendarController();
    CalendarInlineDraft? opened;
    await tester.pumpWidget(
      grid(
        controller: controller,
        onCreateDraft: (_) async {},
        onOpenDraftEditor: (draft) => opened = draft,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('calendar-empty-slot-2026-07-03-1200')),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('确认创建临时日程'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('打开完整日程编辑器'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('打开完整日程编辑器'));
    expect(opened?.startAt, DateTime(2026, 7, 3, 12));
  });
}
