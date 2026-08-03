import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('calendar completes a todo with the Theme V2 PATCH contract', () async {
    late http.Request savedRequest;
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((request) async {
        savedRequest = request;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);
    final record = CalendarRecord.fromTimeline(
      TimelineItem(
        kind: 'asset',
        id: 'todo-1',
        effectiveAt: DateTime(2026, 8, 3, 12),
        title: '完成验收',
        subtitle: '',
        skillName: 'todo',
        sessionId: null,
        payload: const {
          'title': '完成验收',
          'content': 'Theme V2',
          'status': 'pending',
        },
        derived: const {},
      ),
    );

    await updateThemeV2CalendarTodo(api, record);

    expect(savedRequest.method, 'PATCH');
    expect(savedRequest.url.path, '/api/assets/todo-1');
    expect(jsonDecode(savedRequest.body), {
      'payload': {'title': '完成验收', 'content': 'Theme V2', 'status': 'done'},
    });
  });
}
