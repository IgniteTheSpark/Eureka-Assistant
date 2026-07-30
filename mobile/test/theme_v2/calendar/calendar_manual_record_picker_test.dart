import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pet/floating_mascot.dart'
    show mascotSuppressed, releaseMascotSuppress;
import 'package:eureka/theme_v2/calendar/calendar_manual_record_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_test_fixtures.dart';

void main() {
  setUp(() => mascotSuppressed.value = 0);
  tearDown(() {
    while (mascotSuppressed.value > 0) {
      releaseMascotSuppress();
    }
  });

  const options = [
    CalendarSkillOption.event(),
    CalendarSkillOption.asset(
      name: 'todo',
      displayName: '待办',
      icon: '📋',
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
          loader:
              loader ??
              () async => const CalendarSkillCatalog(
                options: options,
                recentNames: ['coffee', 'todo', 'running', 'contact'],
              ),
          onSelected: onSelected ?? (_) {},
          onClose: () {},
        ),
      ),
    );
  }

  testWidgets('shows four recent Skills in one row above the full catalog', (
    tester,
  ) async {
    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();

    expect(find.text('手动记录'), findsOneWidget);
    expect(find.text('选择要记录的 Skill'), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
    expect(find.text('常用'), findsNothing);
    expect(find.text('全部 Skills'), findsOneWidget);
    expect(find.bySemanticsLabel('手动记录：联系人'), findsWidgets);
    expect(find.bySemanticsLabel('手动记录：这是一个很长的跑步训练记录名称'), findsWidgets);
    expect(
      find.byKey(const ValueKey('calendar-skill-all-scroll')),
      findsOneWidget,
    );
    final recentTiles = [
      for (final name in ['coffee', 'todo', 'running', 'contact'])
        find.byKey(ValueKey('calendar-skill-recent-$name')),
    ];
    expect(recentTiles, everyElement(findsOneWidget));
    final tops = [for (final tile in recentTiles) tester.getTopLeft(tile).dy];
    expect(tops.toSet(), hasLength(1));
  });

  testWidgets(
    'recent join deduplicates, omits missing, and never fills holes',
    (tester) async {
      await tester.pumpWidget(
        picker(
          loader: () async => const CalendarSkillCatalog(
            options: options,
            recentNames: ['coffee', 'todo', 'coffee', 'missing'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('calendar-skill-recent-coffee')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-skill-recent-todo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-skill-recent-event')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-skill-recent-missing')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-skill-recent-running')),
        findsNothing,
      );
    },
  );

  testWidgets('empty and unavailable recent states keep all Skills usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      picker(loader: () async => const CalendarSkillCatalog(options: options)),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无'), findsOneWidget);
    expect(find.text('Skill 加载失败'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-skill-all-scroll')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      picker(
        loader: () async => const CalendarSkillCatalog(
          options: options,
          recentUnavailable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近暂不可用'), findsOneWidget);
    expect(find.text('Skill 加载失败'), findsNothing);
    expect(find.bySemanticsLabel('手动记录：咖啡记录'), findsOneWidget);
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
    Future<CalendarSkillCatalog> loader() async {
      loads++;
      if (loads == 1) throw StateError('offline');
      return const CalendarSkillCatalog(
        options: options,
        recentNames: ['coffee'],
      );
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

  testWidgets('modal picker suppresses and then restores the global mascot', (
    tester,
  ) async {
    Future<CalendarSkillOption?>? result;
    await tester.pumpWidget(
      calendarTestHost(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showCalendarManualRecordPicker(
                context,
                effectiveDate: DateTime(2026, 7, 3),
                loader: () async => const CalendarSkillCatalog(
                  options: options,
                  recentNames: ['coffee'],
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    expect(mascotSuppressed.value, 1);

    await tester.tap(find.bySemanticsLabel('关闭手动记录'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(mascotSuppressed.value, 0);
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
    expect(parsed.last.icon, '📋');
  });

  test('recent parser preserves order, deduplicates, and caps at four', () {
    expect(
      parseRecentManualSkillNames({
        'skill_names': [
          'coffee',
          'todo',
          'coffee',
          '',
          null,
          'event',
          'contact',
          'running',
        ],
      }),
      ['coffee', 'todo', 'event', 'contact'],
    );
  });

  test('recent request failure degrades without losing the catalog', () async {
    final api = ApiClient(
      baseUrl: 'https://calendar.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/skills') {
          return _json({
            'skills': [
              {
                'name': 'coffee',
                'display_name': '咖啡记录',
                'user_skill_id': 'coffee-id',
                'enabled': 1,
                'render_spec': {'icon': '☕'},
                'payload_schema': <String, dynamic>{},
              },
            ],
          });
        }
        if (request.url.path == '/api/skills/recent-manual') {
          return _json({'detail': 'offline'}, statusCode: 503);
        }
        throw StateError('unexpected ${request.url}');
      }),
    );
    addTearDown(api.close);

    final catalog = await fetchCalendarSkillCatalog(api);

    expect(catalog.options.map((option) => option.name), ['event', 'coffee']);
    expect(catalog.recentNames, isEmpty);
    expect(catalog.recentUnavailable, isTrue);
  });
}

http.Response _json(Object body, {int statusCode = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
