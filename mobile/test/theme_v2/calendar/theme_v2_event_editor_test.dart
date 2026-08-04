import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pages/create_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_test_fixtures.dart';

void main() {
  testWidgets('core event editor uses the unified Theme V2 chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendarTestHost(
        EventForm(coreRecordsOnly: true, eventId: 'event-1', existing: _event),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('theme-v2-event-editor')), findsOneWidget);
    expect(find.text('编辑日程'), findsOneWidget);
    expect(find.text('EVENT'), findsNothing);
    expect(find.byKey(const ValueKey('theme-v2-event-title')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('theme-v2-event-editor-scroll')),
      const Offset(0, -620),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('theme-v2-event-attendees')),
      findsOneWidget,
    );
  });

  testWidgets('core event editor opens the unified contact selector', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        return switch (request.url.path) {
          '/api/user-skills' => _json([
            {'id': 'skill-contact', 'machine_name': 'contact'},
          ]),
          '/api/assets' => _json(const <Object>[]),
          _ => http.Response('{"detail":"unexpected"}', 500),
        };
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      calendarTestHost(
        EventForm(
          api: api,
          coreRecordsOnly: true,
          eventId: 'event-1',
          existing: _event,
        ),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('theme-v2-event-editor-scroll')),
      const Offset(0, -620),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加联系人'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('theme-v2-contact-selector')),
      findsOneWidget,
    );
    expect(find.text('选择联系人'), findsOneWidget);
    expect(find.text('可选择多个联系人'), findsOneWidget);
  });
}

const _event = <String, dynamic>{
  'title': '产品评审',
  'start_at': '2026-08-05T10:00:00+08:00',
  'end_at': '2026-08-05T11:00:00+08:00',
  'location': '会议室 A',
  'description': '讨论下一版交互',
  'attendees': <Object>[],
};

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
