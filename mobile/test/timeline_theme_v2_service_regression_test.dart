import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads Calendar timeline from Theme V2 core records', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/timeline':
            return http.Response('{"detail":"Not Found"}', 404);
          case '/api/user-skills':
            return _json([
              {
                'id': 'skill-todo',
                'machine_name': 'todo',
                'display_name': '待办',
                'description': '任务',
                'domain': 'work',
                'schema': {
                  'title': {'type': 'string'},
                },
                'created_at': '2026-08-02T00:00:00Z',
                'updated_at': '2026-08-02T00:00:00Z',
              },
            ]);
          case '/api/assets':
            return _json([
              {
                'id': 'asset-todo',
                'user_skill_id': 'skill-todo',
                'payload': {
                  'title': '完成 Theme V2 验收',
                  'due_date': '2026-08-02T10:00:00+08:00',
                  'status': 'open',
                },
                'effective_at': '2026-08-02T02:00:00Z',
                'created_at': '2026-08-01T17:06:00Z',
                'updated_at': '2026-08-01T17:06:00Z',
              },
            ]);
          case '/api/events':
            return _json([
              {
                'id': 'event-review',
                'title': 'Theme V2 设计复核',
                'description': '真机验收测试事件',
                'location': '线上会议室',
                'start_at': '2026-08-02T01:00:00Z',
                'end_at': '2026-08-02T02:00:00Z',
                'all_day': false,
                'status': 'scheduled',
                'created_at': '2026-08-01T17:07:00Z',
                'updated_at': '2026-08-01T17:07:00Z',
              },
            ]);
          default:
            return http.Response('{"detail":"unexpected"}', 500);
        }
      }),
    );
    addTearDown(api.close);

    final items = await fetchTimeline(api);

    expect(items.map((item) => item.id), ['event-review', 'asset-todo']);
    expect(items.first.kind, 'event');
    expect(items.first.location, '线上会议室');
    expect(items.last.kind, 'asset');
    expect(items.last.skillName, 'todo');
    expect(items.last.domain, 'work');
    expect(items.last.hasScheduledTime, isTrue);
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
