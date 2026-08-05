import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_wizard_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uses Theme V2 user-skill draft and create contracts', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/user-skills/draft') {
          return _json({
            'draft': {
              'name': 'running_log',
              'display_name': '跑步记录',
              'payload_schema': {
                'distance': {'type': 'number', 'required': true},
              },
              'render_spec': {'primary_field': 'distance'},
              'sample_payload': {'distance': 5.2},
            },
          });
        }
        return _json({'id': 'skill-running'});
      }),
    );
    addTearDown(api.close);
    final repository = ApiSkillWizardRepository(api);

    await repository.draft({'description': '记录跑步'});
    await repository.confirm({
      'name': 'running_log',
      'display_name': '跑步记录',
      'payload_schema': {
        'distance': {
          'type': 'number',
          'label': '距离',
          'description': '本次跑步距离',
          'required': true,
          'long': false,
        },
        'occurred_date': {
          'type': 'date',
          'label': '日期',
          'description': '实际日期',
          'required': false,
          'long': false,
        },
      },
      'render_spec': {'icon': '🏃', 'primary_field': 'distance'},
      'chat_starters': ['记录一次跑步'],
    });

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /api/user-skills/draft',
      'POST /api/user-skills',
    ]);
    final createBody = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(createBody['machine_name'], 'running_log');
    expect(createBody['schema'], {
      'type': 'object',
      'properties': {
        'distance': {
          'type': 'number',
          'title': '距离',
          'description': '本次跑步距离',
          'x-long': false,
        },
        'occurred_date': {
          'type': 'string',
          'format': 'date',
          'title': '日期',
          'description': '实际日期',
          'x-long': false,
        },
      },
      'required': <String>[],
      'additionalProperties': false,
      'x-capture-enabled': true,
    });
    expect(createBody['render_spec']['icon'], '🏃');
  });
}

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
