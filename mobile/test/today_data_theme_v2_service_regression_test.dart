import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads Today from the Theme V2 core-record list contract', () async {
    final coreListLimits = <int>[];
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if ({
          '/api/assets',
          '/api/events',
          '/api/contacts',
        }.contains(request.url.path)) {
          final limit = int.tryParse(
            request.url.queryParameters['limit'] ?? '',
          );
          if (limit != null) coreListLimits.add(limit);
        }
        switch (request.url.path) {
          case '/api/timeline':
          case '/api/skills':
            return http.Response('{"detail":"Not Found"}', 404);
          case '/api/user-skills':
            return _json([
              {
                'id': 'skill-notes',
                'machine_name': 'notes',
                'display_name': '随记',
                'enabled': true,
                'description': '短笔记',
                'domain': 'knowledge',
                'schema': {
                  'content': {'type': 'string'},
                },
                'created_at': '2026-08-02T00:00:00Z',
                'updated_at': '2026-08-02T00:00:00Z',
              },
              {
                'id': 'skill-todo',
                'machine_name': 'todo',
                'display_name': '待办',
                'enabled': true,
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
                'id': 'asset-note',
                'user_skill_id': 'skill-notes',
                'payload': {'content': 'Theme V2 真机验收记录'},
                'effective_at': '2026-08-01T17:10:00Z',
                'created_at': '2026-08-01T17:05:00Z',
                'updated_at': '2026-08-01T17:05:00Z',
              },
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
          case '/api/contacts':
            return _json({
              'contacts': [
                {
                  'id': 'contact-alex',
                  'name': 'Alex',
                  'company': 'Acme',
                  'title': '设计师',
                  'created_at': '2026-08-01T17:08:00Z',
                },
              ],
            });
          case '/api/flash/sessions/2026-08-02':
            return _json({
              'session': {
                'id': '2026-08-02',
                'recording_count': 2,
                'recordings': [
                  {'id': 'recording-1'},
                  {'id': 'recording-2'},
                ],
              },
            });
          default:
            return http.Response('{"detail":"unexpected"}', 500);
        }
      }),
    );

    final data = await loadToday(
      api,
      nowOverride: DateTime(2026, 8, 2, 1),
      coreRecordsOnly: true,
    );

    expect(data.chain.map((item) => item.id), ['event-review', 'asset-todo']);
    expect(data.pool.map((item) => item.id), [
      'contact-alex',
      'event-review',
      'asset-todo',
      'asset-note',
    ]);
    expect(data.pool.map((item) => item.entityKind), [
      'contact',
      'event',
      'asset',
      'asset',
    ]);
    expect(data.pool.first.type, 'contact');
    expect(data.pool.first.domain, '社交');
    expect(data.poolTrueCount, 4);
    expect(data.flashCount, 2);
    expect(data.flashLatestId, '2026-08-02');
    expect(data.skills['notes']?.label, '随记');
    expect(data.skills['todo']?.label, '待办');
    expect(coreListLimits, isNot(contains(greaterThan(100))));
  });

  test('attaches Today subrequest error handlers before awaiting', () async {
    final uncaught = <Object>[];
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/timeline') {
          return _json({'items': <Object>[]});
        }
        if (request.url.path == '/api/skills') {
          return _json({'skills': <Object>[]});
        }
        if (request.url.path == '/api/sessions') {
          return _json({'sessions': <Object>[]});
        }
        if (request.url.path == '/api/assets') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _json({'assets': <Object>[]});
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    final future = runZonedGuarded(
      () => loadToday(api, nowOverride: DateTime(2026, 8, 2, 1)),
      (error, _) => uncaught.add(error),
    );
    expect(future, isNotNull);
    await future!;

    expect(uncaught, isEmpty);
  });

  test('uses custom skill metadata for a Theme V2 home asset', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/user-skills':
            return _json([
              {
                'id': 'skill-water',
                'machine_name': 'daily_water_intake',
                'display_name': '每日喝水量',
                'enabled': true,
                'domain': '健康',
                'schema': {
                  'type': 'object',
                  'properties': {
                    'amount_ml': {'type': 'number', 'title': '饮水量'},
                  },
                },
                'render_spec': {
                  'icon': '💧',
                  'primary_field': 'amount_ml',
                  'primary_unit': 'ml',
                },
              },
            ]);
          case '/api/assets':
            return _json([
              {
                'id': 'water-1',
                'user_skill_id': 'skill-water',
                'payload': {'amount_ml': 1000},
                'created_at': '2026-08-05T02:00:00Z',
                'updated_at': '2026-08-05T02:00:00Z',
              },
            ]);
          case '/api/events':
            return _json([]);
          case '/api/flash/sessions/2026-08-05':
            return http.Response('{"detail":"not found"}', 404);
          default:
            return http.Response('{"detail":"unexpected"}', 500);
        }
      }),
    );
    addTearDown(api.close);

    final data = await loadToday(
      api,
      nowOverride: DateTime(2026, 8, 5, 12),
      coreRecordsOnly: true,
    );

    expect(data.skills['daily_water_intake']?.label, '每日喝水量');
    expect(data.skills['daily_water_intake']?.icon, '💧');
    expect(data.pool.single.title, '每日喝水量 · 1000 ml');
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
