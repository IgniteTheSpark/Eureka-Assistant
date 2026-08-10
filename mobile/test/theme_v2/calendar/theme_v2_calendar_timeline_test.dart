import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_test_fixtures.dart';

void main() {
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
  });
}

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json'},
);
