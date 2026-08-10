import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_configuration_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'built-in skills expose Chinese field names and field-specific preview values',
    () {
      const expectedLabels = <String, Map<String, String>>{
        'notes': {'title': '标题', 'content': '内容', 'domain': '领域'},
        'todo': {
          'title': '标题',
          'content': '内容',
          'due_date': '截止时间',
          'period': '时段',
          'occurred_at': '发生时间',
          'status': '完成状态',
          'domain': '领域',
        },
        'contact': {
          'name': '姓名',
          'phone': '电话',
          'company': '公司',
          'title': '职位',
          'email': '邮箱',
          'notes': '备注',
          'domain': '领域',
        },
        'event': {
          'title': '标题',
          'start_at': '开始时间',
          'end_at': '结束时间',
          'location': '地点',
          'attendees': '参与人',
          'description': '备注',
        },
      };

      for (final entry in expectedLabels.entries) {
        final properties = <String, dynamic>{
          for (final field in entry.value.keys)
            field: {'type': field == 'attendees' ? 'array' : 'string'},
        };
        final skill = ConfigurableSkill.fromJson({
          'id': 'skill-${entry.key}',
          'machine_name': entry.key,
          'display_name': entry.key,
          'schema': {'type': 'object', 'properties': properties},
          'render_spec': {'primary_field': entry.value.keys.first},
        });

        for (final field in entry.value.entries) {
          expect(
            (skill.payloadSchema[field.key] as Map)['label'],
            field.value,
            reason: '${entry.key}.${field.key}',
          );
          expect(
            skill.samplePayload[field.key],
            field.key == 'attendees' ? [field.value] : field.value,
            reason: 'preview ${entry.key}.${field.key}',
          );
        }
        expect(skill.samplePayload.values, isNot(contains('示例')));
      }
    },
  );

  test('loads one configurable skill and saves presentation only', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _json([
            {
              'id': 'skill-running',
              'machine_name': 'running_log',
              'display_name': '跑步记录',
              'schema': {
                'type': 'object',
                'properties': {
                  'distance': {'type': 'number', 'title': '距离'},
                  'date': {'type': 'string', 'format': 'date', 'title': '日期'},
                },
              },
              'render_spec': {
                'icon': '🏃',
                'primary_field': 'distance',
                'secondary_field': 'date',
                'actions': ['edit'],
              },
            },
          ]);
        }
        return _json({'ok': true});
      }),
    );
    addTearDown(api.close);
    final repository = ApiSkillConfigurationRepository(api);

    final skill = await repository.load('skill-running');
    expect(skill.displayName, '跑步记录');
    expect(skill.samplePayload['distance'], '距离');

    await repository.saveCardDisplay(
      'skill-running',
      CardDisplayConfig(
        primaryFieldId: 'date',
        secondaryFieldIds: const ['distance'],
      ),
      skill.renderSpec,
    );

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'GET /api/user-skills',
      'PATCH /api/user-skills/skill-running',
    ]);
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body.containsKey('payload_schema'), isFalse);
    expect(body['render_spec']['actions'], ['edit']);
    expect(body['render_spec']['card_display'], {
      'primary_field_id': 'date',
      'secondary_field_ids': ['distance'],
    });
  });
}

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
