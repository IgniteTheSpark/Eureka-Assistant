import 'package:eureka/theme_v2/calendar/calendar_manual_record_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  const options = [
    CalendarSkillOption.event(),
    CalendarSkillOption.asset(
      name: 'todo',
      displayName: '待办',
      icon: '✅',
      userSkillId: 'todo-id',
    ),
    CalendarSkillOption.contact(
      displayName: '联系人',
      icon: '📇',
      userSkillId: 'contact-id',
    ),
    CalendarSkillOption.asset(
      name: 'running',
      displayName: '这是一个很长的跑步训练记录名称',
      icon: '🏃',
      userSkillId: 'running-id',
    ),
    CalendarSkillOption.asset(
      name: 'coffee',
      displayName: '咖啡记录',
      icon: '☕',
      userSkillId: 'coffee-id',
    ),
  ];

  Widget picker({
    CalendarSkillLoader? loader,
    ValueChanged<CalendarSkillOption>? onSelected,
  }) {
    return calendarTestHost(
      Align(
        alignment: Alignment.bottomCenter,
        child: CalendarManualRecordPicker(
          effectiveDate: DateTime(2026, 7, 3),
          loader: loader ?? () async => options,
          onSelected: onSelected ?? (_) {},
          onClose: () {},
        ),
      ),
    );
  }

  testWidgets('combines common and all ordered system/custom Skills', (
    tester,
  ) async {
    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();

    expect(find.text('手动记录'), findsOneWidget);
    expect(find.text('选择要记录的 Skill'), findsOneWidget);
    expect(find.text('常用'), findsOneWidget);
    expect(find.text('全部 Skills'), findsOneWidget);
    expect(find.bySemanticsLabel('手动记录：联系人'), findsWidgets);
    expect(find.bySemanticsLabel('手动记录：这是一个很长的跑步训练记录名称'), findsWidgets);
    expect(
      find.byKey(const ValueKey('calendar-skill-all-scroll')),
      findsOneWidget,
    );
  });

  testWidgets('selection only returns the Skill option', (tester) async {
    CalendarSkillOption? selected;
    await tester.pumpWidget(picker(onSelected: (value) => selected = value));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('手动记录：咖啡记录').last);
    expect(selected?.name, 'coffee');
    expect(selected?.userSkillId, 'coffee-id');
  });

  testWidgets('load failure remains in sheet and retries', (tester) async {
    var loads = 0;
    Future<List<CalendarSkillOption>> loader() async {
      loads++;
      if (loads == 1) throw StateError('offline');
      return options;
    }

    await tester.pumpWidget(picker(loader: loader));
    await tester.pumpAndSettle();

    expect(find.text('Skill 加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('手动记录'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.bySemanticsLabel('手动记录：咖啡记录'), findsWidgets);
  });

  test('parsing excludes disabled, deprecated, and non-record Skills', () {
    final parsed = parseCalendarSkillOptions({
      'skills': [
        {
          'name': 'todo',
          'display_name': '待办',
          'user_skill_id': 'todo-id',
          'enabled': 1,
          'render_spec': {'icon': '✅'},
          'payload_schema': <String, dynamic>{},
        },
        {
          'name': 'qa',
          'display_name': '问答',
          'user_skill_id': 'qa-id',
          'enabled': 1,
          'render_spec': {'icon': '❓'},
          'payload_schema': <String, dynamic>{},
        },
        {
          'name': 'hidden',
          'display_name': '已关闭',
          'user_skill_id': 'hidden-id',
          'enabled': 0,
          'render_spec': {'icon': '•'},
          'payload_schema': <String, dynamic>{},
        },
        {
          'name': 'old',
          'display_name': '已废弃',
          'user_skill_id': 'old-id',
          'enabled': 1,
          'deprecated': true,
          'render_spec': {'icon': '•'},
          'payload_schema': <String, dynamic>{},
        },
      ],
    });

    expect(parsed.map((option) => option.name), ['event', 'todo']);
  });
}
