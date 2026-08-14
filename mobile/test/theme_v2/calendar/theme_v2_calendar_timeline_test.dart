import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_dither_surface.dart';
import 'package:flutter/widgets.dart' show StateSetter, StatefulBuilder;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_test_fixtures.dart';

void main() {
  testWidgets('one dither field survives Calendar surface changes', (
    tester,
  ) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    late StateSetter rebuild;
    final day = DateTime(2026, 7, 3);

    await tester.pumpWidget(
      calendarTestHost(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ThemeV2CalendarPage(
              controller: controller,
              today: day,
              initialData: calendarFixtureData(),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final initialState = tester.state(find.byType(ThemeV2DitherField));

    controller.openDay(day);
    rebuild(() {});
    await tester.pump();
    expect(tester.state(find.byType(ThemeV2DitherField)), same(initialState));

    controller.openSchedule();
    rebuild(() {});
    await tester.pump();
    expect(find.byType(ThemeV2DitherField), findsOneWidget);
    expect(tester.state(find.byType(ThemeV2DitherField)), same(initialState));
  });

  testWidgets('production Calendar consumes the authoritative Timeline feed', (
    tester,
  ) async {
    final calls = <String>[];
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path == '/api/timeline') {
          return _json({
            'items': [
              {
                'kind': 'asset',
                'id': 'water-1',
                'effective_at': '2026-08-04T16:00:00Z',
                'created_at': '2026-08-04T16:13:00Z',
                'title': '喝水记录 · 200',
                'subtitle': '',
                'skill_name': 'daily_water_intake',
                'period': '',
                'has_clock_time': false,
                'has_scheduled_time': false,
                'payload': {'amount_ml': 200, 'date': '2026-08-05'},
              },
              for (var index = 1; index <= 3; index++)
                {
                  'kind': 'input_turn',
                  'id': 'capture-$index',
                  'effective_at': '2026-08-04T16:0$index:00Z',
                  'created_at': '2026-08-04T16:0$index:00Z',
                  'title': '硬件闪念 $index',
                  'subtitle': '',
                  'session_id': '2026-08-05',
                  'derived': <String, int>{},
                  'payload': const <String, Object?>{},
                },
            ],
          });
        }
        if (request.url.path == '/api/user-skills') {
          return _json([
            {
              'id': 'water-skill',
              'machine_name': 'daily_water_intake',
              'display_name': '喝水记录',
              'enabled': true,
              'schema': {
                'type': 'object',
                'properties': {
                  'amount_ml': {'type': 'number'},
                },
              },
              'render_spec': {'icon': '💧', 'primary_field': 'amount_ml'},
            },
          ]);
        }
        return _json({
          'detail': 'unexpected ${request.url.path}',
        }, statusCode: 500);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      calendarTestHost(
        ThemeV2CalendarPage(
          api: api,
          today: DateTime(2026, 8, 5),
          onOpenDay: (_) {},
          onOpenRecord: (_) {},
          onOpenFlash: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, contains('/api/timeline'));
    expect(calls, contains('/api/user-skills'));
    expect(calls, isNot(contains('/api/skills')));
    expect(calls, isNot(contains('/api/assets')));
    expect(calls, isNot(contains('/api/flash/recordings')));
    expect(find.text('喝水记录 · 200'), findsOneWidget);
    expect(find.text('✦ 3'), findsOneWidget);
    expect(find.byType(ThemeV2DitherSurface), findsOneWidget);
    final surface = tester.widget<ThemeV2DitherSurface>(
      find.byType(ThemeV2DitherSurface),
    );
    expect(surface.config.flowDirection, const Offset(1, .08));
    await tester.pump();
    final field = tester.widget<ThemeV2DitherField>(
      find.byType(ThemeV2DitherField),
    );
    expect(field.sources, isNotEmpty);
    expect(field.sources.length, lessThanOrEqualTo(24));
    expect(field.sources.every((source) => source.energy == 0), isTrue);
  });
}

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json'},
);
