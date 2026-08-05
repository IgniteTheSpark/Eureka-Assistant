import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:eureka/theme_v2/calendar/calendar_schedule_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  Widget grid({
    CalendarController? controller,
    List<CalendarRecord>? records,
    ValueChanged<CalendarRecord>? onOpenRecord,
    Future<void> Function(CalendarRecord)? onToggleTodo,
    CalendarDraftMutation? onCreateDraft,
    ValueChanged<CalendarInlineDraft>? onOpenDraftEditor,
  }) {
    final data = calendarFixtureData();
    return calendarTestHost(
      CalendarScheduleGrid(
        day: DateTime(2026, 7, 3),
        records: records ?? data.records,
        skills: data.skills,
        controller: controller ?? CalendarController(),
        onOpenRecord: onOpenRecord ?? (_) {},
        onToggleTodo: onToggleTodo ?? (_) async {},
        onCreateDraft: onCreateDraft ?? (_) async {},
        onOpenDraftEditor: onOpenDraftEditor ?? (_) {},
      ),
    );
  }

  List<CalendarRecord> records(
    Iterable<({String id, String title, DateTime at, String kind, bool timed})>
    values,
  ) {
    return [
      for (final value in values)
        CalendarRecord.fromTimeline(
          calendarFixtureItem(
            id: value.id,
            title: value.title,
            at: value.at,
            kind: value.kind == 'event' ? 'event' : 'asset',
            skillName: value.kind == 'todo' ? 'todo' : null,
            endAt: value.kind == 'event'
                ? value.at.add(const Duration(hours: 1))
                : null,
            hasScheduledTime: value.kind == 'todo' && value.timed,
          ),
        ),
    ];
  }

  testWidgets('zero all-day and unscheduled trays allocate no space', (
    tester,
  ) async {
    await tester.pumpWidget(
      grid(
        records: records([
          (
            id: 'meeting',
            title: '讨论会',
            at: DateTime(2026, 7, 3, 9),
            kind: 'event',
            timed: true,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-all-day-tray')), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-unscheduled-tray')),
      findsNothing,
    );
  });

  testWidgets('more than three unscheduled todos stay in a 92px tray', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 3);
    final untimed = records([
      for (var index = 0; index < 4; index++)
        (
          id: 'untimed-$index',
          title: '未排期待办 ${index + 1}',
          at: day.add(Duration(minutes: index)),
          kind: 'todo',
          timed: false,
        ),
    ]);

    await tester.pumpWidget(grid(records: untimed));
    await tester.pumpAndSettle();

    expect(find.text('未排期待办 · 4'), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('calendar-unscheduled-tray')))
          .height,
      92,
    );
    expect(
      find.byKey(const ValueKey('calendar-unscheduled-scroll')),
      findsOneWidget,
    );
  });

  testWidgets('flash originals never enter the unscheduled todo tray', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 3);
    final scheduleRecords = [
      CalendarRecord.fromTimeline(
        calendarFixtureItem(
          id: 'flash-original',
          title: '这是闪念原文',
          at: day,
          kind: 'input_turn',
        ),
      ),
      ...records([
        (
          id: 'actual-todo',
          title: '真正的未排期待办',
          at: day,
          kind: 'todo',
          timed: false,
        ),
      ]),
    ];

    await tester.pumpWidget(grid(records: scheduleRecords));
    await tester.pumpAndSettle();

    expect(find.text('未排期待办 · 1'), findsOneWidget);
    expect(find.text('真正的未排期待办'), findsOneWidget);
    expect(find.text('这是闪念原文'), findsNothing);
  });

  testWidgets('Schedule shows only events and todos and labels todo time', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 3);
    final scheduleRecords = [
      CalendarRecord.fromTimeline(
        calendarFixtureItem(
          id: 'meeting',
          title: '产品会议',
          at: day.add(const Duration(hours: 9)),
          endAt: day.add(const Duration(hours: 10)),
        ),
      ),
      CalendarRecord.fromTimeline(
        calendarFixtureItem(
          id: 'scheduled-todo',
          title: '发送会议纪要',
          at: day.add(const Duration(hours: 10, minutes: 30)),
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: true,
          payload: const {'status': 'pending'},
        ),
      ),
      CalendarRecord.fromTimeline(
        calendarFixtureItem(
          id: 'timed-note',
          title: '不应出现在日程的随记',
          at: day.add(const Duration(hours: 11)),
          kind: 'asset',
          skillName: 'notes',
          hasClockTime: true,
        ),
      ),
    ];

    await tester.pumpWidget(grid(records: scheduleRecords));
    await tester.pumpAndSettle();

    expect(find.text('产品会议'), findsOneWidget);
    expect(find.text('发送会议纪要'), findsOneWidget);
    expect(find.text('不应出现在日程的随记'), findsNothing);
    final todoBlock = find.byKey(
      const ValueKey('calendar-grid-record-scheduled-todo'),
    );
    expect(
      find.descendant(of: todoBlock, matching: find.text('10:30')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: todoBlock, matching: find.text('pending')),
      findsNothing,
    );
  });

  testWidgets('every timed event shows its start and end time', (tester) async {
    final day = DateTime(2026, 7, 3);
    final event = CalendarRecord.fromTimeline(
      calendarFixtureItem(
        id: 'afternoon-review',
        title: '方案评审',
        at: day.add(const Duration(hours: 15, minutes: 30)),
        endAt: day.add(const Duration(hours: 16)),
      ),
    );

    await tester.pumpWidget(grid(records: [event]));
    await tester.pumpAndSettle();

    final block = find.byKey(
      const ValueKey('calendar-grid-record-afternoon-review'),
    );
    expect(
      find.descendant(of: block, matching: find.text('15:30–16:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: block, matching: find.text('方案评审')),
      findsOneWidget,
    );
  });

  testWidgets(
    'meeting training and same-minute todo band remain three blocks',
    (tester) async {
      final at = DateTime(2026, 7, 3, 14, 30);
      final sameTime = records([
        (id: 'meeting', title: '小型讨论会', at: at, kind: 'event', timed: true),
        (id: 'training', title: '培训', at: at, kind: 'event', timed: true),
        for (var index = 0; index < 3; index++)
          (
            id: 'todo-$index',
            title: '待办 ${index + 1}',
            at: at.add(Duration(seconds: index)),
            kind: 'todo',
            timed: true,
          ),
      ]);

      await tester.pumpWidget(grid(records: sameTime));
      await tester.pumpAndSettle();

      final blocks = [
        tester.getRect(
          find.byKey(const ValueKey('calendar-grid-record-meeting')),
        ),
        tester.getRect(
          find.byKey(const ValueKey('calendar-grid-record-training')),
        ),
        tester.getRect(find.bySemanticsLabel('展开 3 个待办')),
      ];
      expect(blocks.map((rect) => rect.left).toSet(), hasLength(3));
      expect(blocks[0].right <= blocks[1].left, isTrue);
      expect(blocks[1].right <= blocks[2].left, isTrue);
    },
  );

  testWidgets('todo checkbox toggles the individual record', (tester) async {
    final at = DateTime(2026, 7, 3, 15);
    final todoRecords = records([
      (id: 'todo-a', title: '确认计划', at: at, kind: 'todo', timed: true),
      (
        id: 'todo-b',
        title: '补充记录',
        at: at.add(const Duration(seconds: 1)),
        kind: 'todo',
        timed: true,
      ),
    ]);
    CalendarRecord? toggled;
    await tester.pumpWidget(
      grid(
        records: todoRecords,
        onToggleTodo: (record) async => toggled = record,
      ),
    );
    await tester.pumpAndSettle();
    final band = find.bySemanticsLabel('展开 2 个待办');
    await tester.ensureVisible(band);
    await tester.pumpAndSettle();
    await tester.tap(band);
    await tester.pumpAndSettle();

    final checkbox = find.bySemanticsLabel('完成待办：确认计划');
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();

    expect(toggled?.id, 'todo-a');
  });

  testWidgets('a single scheduled todo still exposes completion', (
    tester,
  ) async {
    final todoRecords = records([
      (
        id: 'solo-todo',
        title: '单个日程待办',
        at: DateTime(2026, 7, 3, 15),
        kind: 'todo',
        timed: true,
      ),
    ]);
    CalendarRecord? toggled;
    await tester.pumpWidget(
      grid(
        records: todoRecords,
        onToggleTodo: (record) async => toggled = record,
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.bySemanticsLabel('完成待办：单个日程待办');
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();

    expect(toggled?.id, 'solo-todo');
  });

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
    final band = find.bySemanticsLabel('展开 2 个待办');
    await tester.ensureVisible(band);
    await tester.pumpAndSettle();
    final collapsedTop = tester.getTopLeft(laterFinder).dy;

    expect(find.text('2 个待办'), findsOneWidget);
    expect(find.text('回访客户'), findsNothing);
    await tester.tap(band);
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
    expect(visual.height, closeTo(22, 0.01));
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
    expect(
      find.byKey(const ValueKey('calendar-empty-slot-2026-07-03-2330')),
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

  testWidgets('lower half-hour has its own 44px draft target', (tester) async {
    final controller = CalendarController();
    await tester.pumpWidget(grid(controller: controller, records: const []));
    await tester.pumpAndSettle();

    final upper = find.byKey(
      const ValueKey('calendar-empty-slot-2026-07-03-1400'),
    );
    final lower = find.byKey(
      const ValueKey('calendar-empty-slot-2026-07-03-1430'),
    );
    await tester.ensureVisible(lower);
    expect(upper, findsOneWidget);
    expect(lower, findsOneWidget);
    expect(tester.getRect(upper).height, greaterThanOrEqualTo(44));
    expect(tester.getRect(lower).height, greaterThanOrEqualTo(44));
    expect(
      tester.getRect(upper).bottom,
      closeTo(tester.getRect(lower).top, 0.01),
    );

    await tester.tap(lower);
    await tester.pump();

    expect(controller.inlineDraft?.startAt, DateTime(2026, 7, 3, 14, 30));
    expect(controller.inlineDraft?.endAt, DateTime(2026, 7, 3, 15));
    expect(find.text('14:30–15:00'), findsOneWidget);
  });

  testWidgets('inline draft shows its explicit start and end time', (
    tester,
  ) async {
    final controller = CalendarController();
    await tester.pumpWidget(grid(controller: controller, records: const []));
    await tester.pumpAndSettle();

    final slot = find.byKey(
      const ValueKey('calendar-empty-slot-2026-07-03-1600'),
    );
    await tester.ensureVisible(slot);
    await tester.tap(slot);
    await tester.pump();

    expect(find.text('16:00–16:30'), findsOneWidget);
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
