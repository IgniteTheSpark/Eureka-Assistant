import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'loads an event detail from the Theme V2 core-record endpoint',
    () async {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient((request) async {
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
      ).load(const AssetEntityRef(kind: AssetEntityKind.event, id: 'event-1'));

      expect(detail.ref.kind, AssetEntityKind.event);
      expect(detail.ref.id, 'event-1');
      expect(detail.skill.displayName, '事件');
      expect(detail.display.primaryFieldId, 'title');
      expect(detail.values['title'], 'Theme V2 设计复核');
      expect(detail.values['location'], '线上会议室');
      expect(detail.capabilities.editable, isFalse);
    },
  );

  test('loads an asset detail with its Theme V2 user skill metadata', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
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
              'content': {'type': 'string'},
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
    ).load(const AssetEntityRef(kind: AssetEntityKind.asset, id: 'asset-1'));

    expect(detail.ref.kind, AssetEntityKind.asset);
    expect(detail.skill.machineName, 'notes');
    expect(detail.skill.displayName, '随记');
    expect(detail.display.primaryFieldId, 'content');
    expect(detail.values['content'], 'Theme V2 真机验收记录');
    expect(detail.capabilities.editable, isFalse);
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
