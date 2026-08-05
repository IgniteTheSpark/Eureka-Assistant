import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_model.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'loads an event detail from the Theme V2 core-record endpoint',
    () async {
      final requests = <String>[];
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path == '/api/asset-details/event/event-1') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.url.path == '/api/events/event-1') {
            return _json({
              'id': 'event-1',
              'title': 'Theme V2 设计复核',
              'description': '真机验收测试事件',
              'location': '线上会议室',
              'start_at': '2026-08-02T01:00:00Z',
              'end_at': '2026-08-02T02:00:00Z',
              'all_day': false,
              'status': 'scheduled',
              'created_at': '2026-08-01T17:07:00Z',
              'updated_at': '2026-08-01T17:08:00Z',
            });
          }
          return http.Response('{"detail":"unexpected"}', 500);
        }),
      );
      addTearDown(api.close);

      final detail = await ApiAssetDetailRepository(
        api,
        coreRecordsOnly: true,
      ).load(const AssetEntityRef(kind: AssetEntityKind.event, id: 'event-1'));

      expect(detail.ref.kind, AssetEntityKind.event);
      expect(detail.ref.id, 'event-1');
      expect(detail.skill.displayName, '事件');
      expect(detail.display.primaryFieldId, 'title');
      expect(detail.values['title'], 'Theme V2 设计复核');
      expect(detail.values['location'], '线上会议室');
      expect(detail.values.keys, {
        'title',
        'start_at',
        'end_at',
        'location',
        'attendees',
        'description',
      });
      expect(detail.capabilities.editable, isTrue);
      expect(requests, ['/api/events/event-1']);
    },
  );

  test('core event exposes attendees and its originating flash', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient(
        (request) async => _json({
          'id': 'event-1',
          'title': '参加饭局',
          'description': null,
          'location': null,
          'start_at': '2026-08-03T10:00:00Z',
          'end_at': '2026-08-03T11:00:00Z',
          'all_day': false,
          'status': 'scheduled',
          'attendees': [
            {
              'id': 'attendee-1',
              'contact_id': null,
              'name_raw': '冯总',
              'display_name': '冯总',
              'is_resolved': false,
              'contact_summary': '',
            },
          ],
          'source_recording_id': 'recording-1',
          'source_input_turn_id': 'turn-1',
          'created_at': '2026-08-02T10:00:00Z',
          'updated_at': '2026-08-02T10:00:00Z',
        }),
      ),
    );
    addTearDown(api.close);

    final detail = await ApiAssetDetailRepository(
      api,
      coreRecordsOnly: true,
    ).load(const AssetEntityRef(kind: AssetEntityKind.event, id: 'event-1'));

    expect(detail.fields.map((field) => field.id), contains('attendees'));
    expect(
      (detail.values['attendees'] as List).single,
      containsPair('name_raw', '冯总'),
    );
    expect(
      (detail.values['attendees'] as List).single,
      containsPair('id', 'attendee-1'),
    );
    expect(detail.source.kind, AssetDetailSourceKind.flash);
    expect(detail.source.label, '来自 8月2日闪念');
    expect(detail.source.sessionId, 'recording-1');
    expect(detail.source.inputTurnId, 'turn-1');
    expect(detail.source.canOpen, isTrue);
  });

  test('loads an asset detail with its Theme V2 user skill metadata', () async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/api/asset-details/asset/asset-1') {
          return http.Response('{"detail":"Not Found"}', 404);
        }
        if (request.url.path == '/api/assets/asset-1') {
          return _json({
            'id': 'asset-1',
            'user_skill_id': 'skill-notes',
            'payload': {'content': 'Theme V2 真机验收记录'},
            'effective_at': '2026-08-01T17:10:00Z',
            'created_at': '2026-08-01T17:05:00Z',
            'updated_at': '2026-08-01T17:06:00Z',
          });
        }
        if (request.url.path == '/api/user-skills/skill-notes') {
          return _json({
            'id': 'skill-notes',
            'machine_name': 'notes',
            'display_name': '随记',
            'description': '短笔记',
            'domain': 'knowledge',
            'schema': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
                'content': {'type': 'string'},
                'tags': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
              'required': ['title', 'content'],
              'additionalProperties': false,
              'x-capture-enabled': true,
            },
            'created_at': '2026-08-01T17:00:00Z',
            'updated_at': '2026-08-01T17:00:00Z',
          });
        }
        return http.Response('{"detail":"unexpected"}', 500);
      }),
    );
    addTearDown(api.close);

    final detail = await ApiAssetDetailRepository(
      api,
      coreRecordsOnly: true,
    ).load(const AssetEntityRef(kind: AssetEntityKind.asset, id: 'asset-1'));

    expect(detail.ref.kind, AssetEntityKind.asset);
    expect(detail.skill.machineName, 'notes');
    expect(detail.skill.displayName, '随记');
    expect(detail.display.primaryFieldId, 'content');
    expect(detail.fields.map((field) => field.id), [
      'title',
      'content',
      'tags',
    ]);
    expect(
      detail.fields.where((field) => field.required).map((field) => field.id),
      ['title', 'content'],
    );
    expect(detail.values['content'], 'Theme V2 真机验收记录');
    expect(detail.capabilities.editable, isTrue);
    expect(requests, ['/api/assets/asset-1', '/api/user-skills/skill-notes']);
  });

  test(
    'core custom asset keeps its configured presentation metadata',
    () async {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient((request) async {
          if (request.url.path == '/api/assets/water-1') {
            return _json({
              'id': 'water-1',
              'user_skill_id': 'skill-water',
              'payload': {'date': '2026-08-05', 'amount_ml': 200},
              'created_at': '2026-08-05T12:00:00Z',
              'updated_at': '2026-08-05T12:00:00Z',
            });
          }
          if (request.url.path == '/api/user-skills/skill-water') {
            return _json({
              'id': 'skill-water',
              'machine_name': 'daily_water_intake',
              'display_name': '每日喝水量',
              'schema': {
                'type': 'object',
                'properties': {
                  'date': {'type': 'string', 'title': '日期'},
                  'amount_ml': {'type': 'number', 'title': '饮水量'},
                },
              },
              'render_spec': {
                'icon': '💧',
                'primary_field': 'amount_ml',
                'secondary_field': 'date',
              },
            });
          }
          return http.Response('{"detail":"unexpected"}', 500);
        }),
      );
      addTearDown(api.close);

      final detail = await ApiAssetDetailRepository(
        api,
        coreRecordsOnly: true,
      ).load(const AssetEntityRef(kind: AssetEntityKind.asset, id: 'water-1'));

      expect(detail.skill.icon, '💧');
      expect(detail.display.primaryFieldId, 'amount_ml');
      expect(
        detail.fields.singleWhere((field) => field.id == 'amount_ml').label,
        '饮水量',
      );
    },
  );

  test(
    'aligns a core expense detail with the legacy content contract',
    () async {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient((request) async {
          if (request.url.path == '/api/assets/expense-1') {
            return _json({
              'id': 'expense-1',
              'user_skill_id': 'skill-expense',
              'payload': {
                'amount': 386,
                'currency': 'CNY',
                'description': '晚餐',
                'occurred_at': '2026-08-02T19:00:00+08:00',
              },
              'effective_at': null,
              'created_at': '2026-08-02T13:43:21Z',
              'updated_at': '2026-08-02T13:43:21Z',
            });
          }
          if (request.url.path == '/api/user-skills/skill-expense') {
            return _json({
              'id': 'skill-expense',
              'machine_name': 'expense',
              'display_name': '消费',
              'domain': 'finance',
              'schema': {
                'type': 'object',
                'properties': {
                  'date': {'type': 'string'},
                  'amount': {'type': 'number'},
                  'domain': {'type': 'string'},
                  'period': {'type': 'string'},
                  'category': {'type': 'string'},
                  'currency': {'type': 'string'},
                  'merchant': {'type': 'string'},
                  'description': {'type': 'string'},
                  'occurred_at': {'type': 'string'},
                },
                'required': ['amount', 'currency'],
              },
            });
          }
          return http.Response('{"detail":"unexpected"}', 500);
        }),
      );
      addTearDown(api.close);

      final detail = await ApiAssetDetailRepository(api, coreRecordsOnly: true)
          .load(
            const AssetEntityRef(kind: AssetEntityKind.asset, id: 'expense-1'),
          );

      final labels = {for (final field in detail.fields) field.id: field.label};
      expect(detail.display.primaryFieldId, 'amount');
      expect(labels, containsPair('amount', '金额'));
      expect(labels, containsPair('currency', '币种'));
      expect(detail.values.keys, {'amount', 'currency', 'description'});
    },
  );

  test('core todo shows occurred_at as its user-facing due time', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/assets/todo-1') {
          return _json({
            'id': 'todo-1',
            'user_skill_id': 'skill-todo',
            'payload': {
              'title': '参加饭局',
              'occurred_at': '2026-08-03T18:00:00+08:00',
            },
            'effective_at': null,
            'created_at': '2026-08-02T10:00:00Z',
            'updated_at': '2026-08-02T10:00:00Z',
          });
        }
        return _json({
          'id': 'skill-todo',
          'machine_name': 'todo',
          'display_name': '待办',
          'schema': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'due_date': {'type': 'string'},
              'occurred_at': {'type': 'string'},
            },
          },
        });
      }),
    );
    addTearDown(api.close);

    final detail = await ApiAssetDetailRepository(
      api,
      coreRecordsOnly: true,
    ).load(const AssetEntityRef(kind: AssetEntityKind.asset, id: 'todo-1'));

    expect(detail.values['due_date'], '2026-08-03T18:00:00+08:00');
    expect(detail.values, isNot(contains('occurred_at')));
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
