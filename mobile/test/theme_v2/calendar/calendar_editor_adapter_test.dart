import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pages/calendar_page.dart';
import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_test_fixtures.dart';

void main() {
  testWidgets('editing a created event fetches its complete existing record', (
    tester,
  ) async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode({
            'event': {
              'event_id': 'event-created',
              'title': '完整标题',
              'location': '会议室 A',
              'description': '完整描述',
              'start_at': '2026-07-03T09:00:00+08:00',
              'end_at': '2026-07-03T10:30:00+08:00',
              'all_day': 0,
              'attendees': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);
    String? result = 'pending';
    final draft = CalendarInlineDraft(
      startAt: DateTime(2026, 7, 3, 8),
      endAt: DateTime(2026, 7, 3, 8, 30),
    );

    await tester.pumpWidget(
      calendarLegacyRouteTestHost(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await openCalendarInlineDraftEditor(
                context,
                draft,
                eventId: 'event-created',
                api: api,
              );
            },
            child: const Text('编辑'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(requests, ['GET /api/events/event-created']);
    expect(find.text('完整标题'), findsWidgets);
    expect(find.text('会议室 A'), findsOneWidget);
    expect(find.text('2026-07-03 09:00'), findsOneWidget);
    expect(find.text('2026-07-03 10:30'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('完整描述'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a create editor resolves null without async errors', (
    tester,
  ) async {
    final completed = Completer<String?>();
    final draft = CalendarInlineDraft(
      startAt: DateTime(2026, 7, 3, 8),
      endAt: DateTime(2026, 7, 3, 8, 30),
    );

    await tester.pumpWidget(
      calendarLegacyRouteTestHost(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              completed.complete(
                await openCalendarInlineDraftEditor(context, draft),
              );
            },
            child: const Text('创建'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await completed.future, isNull);
    expect(tester.takeException(), isNull);
  });
}
