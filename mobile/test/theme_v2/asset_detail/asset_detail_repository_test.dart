import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_model.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('repository loads one normalized canonical detail envelope', () async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode(_detailJson()),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    final repository = ApiAssetDetailRepository(api);

    final model = await repository.load(
      const AssetEntityRef(kind: AssetEntityKind.asset, id: 'asset-1'),
    );

    expect(model.ref.kind, AssetEntityKind.asset);
    expect(model.version, 'version-1');
    expect(model.skill.displayName, '宝贝饮食');
    expect(model.fields.map((field) => field.id), ['meal', 'remark']);
    expect(model.fields.last.long, isTrue);
    expect(model.values['remark'], startsWith('# 晚餐'));
    expect(model.display.primaryFieldId, 'meal');
    expect(model.source.kind, AssetDetailSourceKind.flash);
    expect(model.source.sessionId, 'session-1');
    expect(model.source.inputTurnId, 'turn-2');
    expect(model.source.canOpen, isTrue);
    expect(model.capabilities.editable, isTrue);
    expect(requests, ['GET /api/asset-details/asset/asset-1']);
  });

  test(
    'save carries the authoritative version and returns the next model',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(_detailJson(version: 'version-2', remark: '已保存')),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      final repository = ApiAssetDetailRepository(api);
      final current = AssetDetailModel.fromJson(_detailJson());

      final saved = await repository.save(current, const {'remark': '已保存'});

      expect(saved.version, 'version-2');
      expect(saved.values['remark'], '已保存');
      expect(requests.single.method, 'PUT');
      expect(requests.single.url.path, '/api/asset-details/asset/asset-1');
      expect(jsonDecode(requests.single.body), {
        'expected_version': 'version-1',
        'values_patch': {'remark': '已保存'},
      });
    },
  );

  test('manual source is static', () {
    final json = _detailJson();
    json['source'] = {
      'kind': 'manual',
      'label': '手动创建',
      'session_id': null,
      'input_turn_id': null,
    };

    final model = AssetDetailModel.fromJson(json);

    expect(model.source.kind, AssetDetailSourceKind.manual);
    expect(model.source.canOpen, isFalse);
  });

  test('core todo toggle preserves payload and uses PATCH', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/user-skills/skill-todo') {
          return http.Response(
            jsonEncode({
              'id': 'skill-todo',
              'machine_name': 'todo',
              'display_name': '待办',
              'schema': {
                'type': 'object',
                'properties': {
                  'title': {'type': 'string'},
                  'content': {'type': 'string'},
                  'status': {'type': 'string'},
                },
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        final payload = request.method == 'PATCH'
            ? (jsonDecode(request.body) as Map<String, dynamic>)['payload']
            : {
                'title': '完成验收',
                'content': '不能丢失',
                'status': 'pending',
                'domain': 'productivity',
              };
        return http.Response(
          jsonEncode({
            'id': 'todo-1',
            'user_skill_id': 'skill-todo',
            'payload': payload,
            'created_at': '2026-08-03T02:00:00Z',
            'updated_at': '2026-08-03T02:00:00Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);
    final repository = ApiAssetDetailRepository(api, coreRecordsOnly: true);
    final current = await repository.load(
      const AssetEntityRef(kind: AssetEntityKind.asset, id: 'todo-1'),
    );

    final saved = await repository.save(current, const {'status': 'done'});

    final patch = requests.singleWhere((request) => request.method == 'PATCH');
    expect(patch.url.path, '/api/assets/todo-1');
    expect(jsonDecode(patch.body), {
      'payload': {
        'title': '完成验收',
        'content': '不能丢失',
        'status': 'done',
        'domain': 'productivity',
      },
    });
    expect(saved.values['status'], 'done');
  });

  test('core expense detail uses the canonical payment glyph', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/user-skills/skill-expense') {
          return http.Response(
            jsonEncode({
              'id': 'skill-expense',
              'machine_name': 'expense',
              'display_name': '记账',
              'schema': const {},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'expense-1',
            'user_skill_id': 'skill-expense',
            'payload': {'amount': 88},
            'created_at': '2026-08-03T03:00:00Z',
            'updated_at': '2026-08-03T03:00:00Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);
    final repository = ApiAssetDetailRepository(api, coreRecordsOnly: true);

    final detail = await repository.load(
      const AssetEntityRef(kind: AssetEntityKind.asset, id: 'expense-1'),
    );

    expect(detail.skill.icon, '💳');
  });

  test('closed custom schema hides polluted payload-only fields', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/user-skills/skill-running') {
          return http.Response(
            jsonEncode({
              'id': 'skill-running',
              'machine_name': 'running_log',
              'display_name': '跑步记录',
              'schema': {
                'type': 'object',
                'properties': {
                  'distance': {'type': 'number', 'label': '距离'},
                },
                'required': ['distance'],
                'additionalProperties': false,
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'run-1',
            'user_skill_id': 'skill-running',
            'payload': {'distance': 5, 'acceptance_marker': 'must not render'},
            'created_at': '2026-08-03T03:00:00Z',
            'updated_at': '2026-08-03T03:00:00Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);
    final repository = ApiAssetDetailRepository(api, coreRecordsOnly: true);

    final detail = await repository.load(
      const AssetEntityRef(kind: AssetEntityKind.asset, id: 'run-1'),
    );

    expect(detail.fields.map((field) => field.id), ['distance']);
    expect(detail.values, {'distance': 5});
    expect(detail.values, isNot(contains('acceptance_marker')));
  });

  test(
    'core report todo exposes report provenance outside editable fields',
    () async {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient((request) async {
          if (request.url.path == '/api/user-skills/skill-todo') {
            return http.Response(
              jsonEncode({
                'id': 'skill-todo',
                'machine_name': 'todo',
                'display_name': '待办',
                'schema': {
                  'type': 'object',
                  'properties': {
                    'title': {'type': 'string'},
                    'due_date': {'type': 'string'},
                  },
                },
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'todo-report-1',
              'user_skill_id': 'skill-todo',
              'payload': {'title': '整理验收清单'},
              'source_report_id': 'report-1',
              'source_report_action_id': 'action-1',
              'source_report_title': '月度复盘',
              'created_at': '2026-08-03T03:00:00Z',
              'updated_at': '2026-08-03T03:00:00Z',
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(api.close);
      final repository = ApiAssetDetailRepository(api, coreRecordsOnly: true);

      final detail = await repository.load(
        const AssetEntityRef(kind: AssetEntityKind.asset, id: 'todo-report-1'),
      );

      expect(detail.source.kind, AssetDetailSourceKind.report);
      expect(detail.source.label, '来自报告《月度复盘》');
      expect(detail.source.reportId, 'report-1');
      expect(detail.source.canOpen, isTrue);
      expect(
        detail.fields.map((field) => field.id),
        isNot(
          containsAll(const [
            'source_report_id',
            'source_report_action_id',
            'source_report_title',
          ]),
        ),
      );
      expect(detail.values, isNot(contains('source_report_id')));
    },
  );

  test('deleted source report keeps its title but cannot be opened', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/user-skills/skill-todo') {
          return http.Response(
            jsonEncode({
              'id': 'skill-todo',
              'machine_name': 'todo',
              'display_name': '待办',
              'schema': const {},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'todo-report-deleted',
            'user_skill_id': 'skill-todo',
            'payload': {'title': '跟进事项'},
            'source_report_id': null,
            'source_report_action_id': 'action-deleted',
            'source_report_title': '月度复盘',
            'created_at': '2026-08-03T03:00:00Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);
    final repository = ApiAssetDetailRepository(api, coreRecordsOnly: true);

    final detail = await repository.load(
      const AssetEntityRef(
        kind: AssetEntityKind.asset,
        id: 'todo-report-deleted',
      ),
    );

    expect(detail.source.kind, AssetDetailSourceKind.report);
    expect(detail.source.label, '来自报告《月度复盘》');
    expect(detail.source.reportId, isNull);
    expect(detail.source.canOpen, isFalse);
  });

  test('capture provenance takes priority over report provenance', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/user-skills/skill-todo') {
          return http.Response(
            jsonEncode({
              'id': 'skill-todo',
              'machine_name': 'todo',
              'display_name': '待办',
              'schema': const {},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'todo-mixed-source',
            'user_skill_id': 'skill-todo',
            'payload': {'title': '跟进事项'},
            'source_recording_id': 'recording-1',
            'source_input_turn_id': 'turn-1',
            'source_report_id': 'report-1',
            'source_report_action_id': 'action-1',
            'source_report_title': '月度复盘',
            'created_at': '2026-08-03T03:00:00Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);
    final repository = ApiAssetDetailRepository(api, coreRecordsOnly: true);

    final detail = await repository.load(
      const AssetEntityRef(
        kind: AssetEntityKind.asset,
        id: 'todo-mixed-source',
      ),
    );

    expect(detail.source.kind, AssetDetailSourceKind.flash);
    expect(detail.source.sessionId, 'recording-1');
    expect(detail.source.reportId, isNull);
  });
}

Map<String, dynamic> _detailJson({
  String version = 'version-1',
  String remark = '# 晚餐\n\n- 主动吃',
}) => {
  'entity': {'kind': 'asset', 'id': 'asset-1', 'version': version},
  'skill': {
    'id': 'skill-1',
    'machine_name': 'baby_meal',
    'display_name': '宝贝饮食',
    'icon': '🍼',
  },
  'fields': [
    {
      'id': 'remark',
      'label': '备注',
      'type': 'string',
      'required': false,
      'long': true,
      'order': 1,
    },
    {
      'id': 'meal',
      'label': '饮食',
      'type': 'string',
      'required': true,
      'long': false,
      'order': 0,
    },
  ],
  'values': {'meal': '小米粥', 'remark': remark},
  'display': {
    'primary_field_id': 'meal',
    'secondary_field_ids': ['remark'],
  },
  'source': {
    'kind': 'flash',
    'label': '来自闪念',
    'session_id': 'session-1',
    'input_turn_id': 'turn-2',
  },
  'capabilities': {'editable': true, 'deletable': true},
};
