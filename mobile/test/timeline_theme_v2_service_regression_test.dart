import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('asset aliases and expense share canonical glyphs', () {
    expect(resolveMeta('todo', const {}).icon, '📋');
    expect(resolveMeta('calendar', const {}).icon, '📅');
    expect(resolveMeta('note', const {}).icon, '✍️');
    expect(resolveMeta('idea', const {}).icon, '✍️');
    expect(resolveMeta('misc', const {}).icon, '✍️');
    expect(resolveMeta('expense', const {}).icon, '💳');
    expect(resolveMeta('unknown', const {}).icon, '•');
  });

  test('custom skill registry keeps its configured glyph', () {
    const registry = {'tennis': SkillMeta('🎾', '网球记录', 'green')};

    expect(resolveMeta('tennis', registry).icon, '🎾');
  });

  test('stale registry glyphs cannot override built-in identities', () {
    const registry = {
      'expense': SkillMeta('🍔', '消费', 'green'),
      'contact': SkillMeta('🪪', '联系人', 'neutral'),
    };

    expect(resolveMeta('expense', registry).icon, '💳');
    expect(resolveMeta('contact', registry).icon, '👤');
  });

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
          case '/api/contacts':
            return _json({
              'contacts': [
                {
                  'id': 'contact-alex',
                  'name': 'Alex',
                  'company': 'Acme',
                  'title': '设计师',
                  'created_at': '2026-08-02T02:30:00Z',
                },
              ],
            });
          case '/api/flash/recordings':
            return _json({
              'recordings': [
                {
                  'id': 'recording-1',
                  'title': 'Theme V2 闪念',
                  'session_date': '2026-08-02',
                  'captured_at': '2026-08-02T03:00:00Z',
                  'process_status': 'completed',
                },
              ],
            });
          default:
            return http.Response('{"detail":"unexpected"}', 500);
        }
      }),
    );
    addTearDown(api.close);

    final items = await fetchTimeline(api);

    expect(items.map((item) => item.id), [
      'event-review',
      'asset-todo',
      'contact-alex',
      'recording-1',
    ]);
    expect(items.first.kind, 'event');
    expect(items.first.location, '线上会议室');
    expect(items[1].kind, 'asset');
    expect(items[1].skillName, 'todo');
    expect(items[1].domain, 'work');
    expect(items[1].hasScheduledTime, isTrue);
    expect(items[2].kind, 'contact');
    expect(items[2].contactId, 'contact-alex');
    expect(items[2].title, 'Alex');
    expect(items[2].subtitle, 'Acme · 设计师');
    expect(items.last.kind, 'input_turn');
    expect(items.last.sessionId, '2026-08-02');
    expect(items.last.title, 'Theme V2 闪念');
  });

  test('keeps Theme V2 assets in Flow when effective_at is omitted', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/user-skills':
            return _json([
              {
                'id': 'skill-expense',
                'machine_name': 'expense',
                'display_name': '消费',
                'domain': 'finance',
                'schema': const {},
              },
              {
                'id': 'skill-notes',
                'machine_name': 'notes',
                'display_name': '随记',
                'domain': 'knowledge',
                'schema': const {},
              },
            ]);
          case '/api/assets':
            return _json([
              {
                'id': 'asset-expense',
                'user_skill_id': 'skill-expense',
                'payload': {
                  'amount': 386,
                  'occurred_at': '2026-08-02T19:00:00+08:00',
                },
                'effective_at': null,
                'created_at': '2026-08-02T10:00:00Z',
                'updated_at': '2026-08-02T10:00:00Z',
              },
              {
                'id': 'asset-notes',
                'user_skill_id': 'skill-notes',
                'payload': {'content': '没有显式时间的闪念'},
                'effective_at': null,
                'created_at': '2026-08-02T12:00:00Z',
                'updated_at': '2026-08-02T12:00:00Z',
              },
            ]);
          case '/api/events':
            return _json([]);
          case '/api/contacts':
            return _json({'contacts': <Object>[]});
          case '/api/flash/recordings':
            return _json({'recordings': <Object>[]});
          default:
            return http.Response('{"detail":"unexpected"}', 500);
        }
      }),
    );
    addTearDown(api.close);

    final items = await fetchTimeline(api, coreRecordsOnly: true);

    expect(items.map((item) => item.id), ['asset-expense', 'asset-notes']);
    expect(items.first.effectiveAt.hour, 19);
    expect(items.first.hasClockTime, isTrue);
    expect(items.last.effectiveAt.hour, 20);
    expect(items.last.hasClockTime, isFalse);
    expect(items.last.hasScheduledTime, isFalse);
  });

  test('orders equal effective times by creation time and id', () {
    final effectiveAt = DateTime(2026, 8, 5, 9);
    TimelineItem item(String id, DateTime createdAt) => TimelineItem(
      kind: 'asset',
      id: id,
      effectiveAt: effectiveAt,
      createdAt: createdAt,
      title: id,
      subtitle: '',
      skillName: 'notes',
      sessionId: null,
      derived: const {},
    );
    final items = [
      item('b', DateTime(2026, 8, 5, 8, 1)),
      item('c', DateTime(2026, 8, 5, 8)),
      item('a', DateTime(2026, 8, 5, 8, 1)),
    ]..sort(compareTimelineItems);

    expect(items.map((item) => item.id), ['c', 'a', 'b']);
  });

  test('core skill metadata uses the same built-in icons as detail', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient(
        (request) async => _json([
          {
            'id': 'skill-expense',
            'machine_name': 'expense',
            'display_name': '消费',
            'schema': const {},
          },
          {
            'id': 'skill-todo',
            'machine_name': 'todo',
            'display_name': '待办',
            'schema': const {},
          },
        ]),
      ),
    );
    addTearDown(api.close);

    final skills = await fetchSkills(api, coreRecordsOnly: true);

    expect(skills['expense']?.icon, '💳');
    expect(skills['todo']?.icon, '📋');
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
