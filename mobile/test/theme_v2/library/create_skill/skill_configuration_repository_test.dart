import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_configuration_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads one configurable skill and saves presentation only', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _json({
            'skills': [
              {
                'user_skill_id': 'skill-running',
                'name': 'running_log',
                'display_name': '跑步记录',
                'payload_schema': {
                  'distance': {'type': 'number', 'label': '距离'},
                  'date': {'type': 'date', 'label': '日期'},
                },
                'render_spec': {
                  'icon': '🏃',
                  'primary_field': 'distance',
                  'secondary_field': 'date',
                  'actions': ['edit'],
                },
              },
            ],
          });
        }
        return _json({'ok': true});
      }),
    );
    addTearDown(api.close);
    final repository = ApiSkillConfigurationRepository(api);

    final skill = await repository.load('skill-running');
    expect(skill.displayName, '跑步记录');
    expect(skill.samplePayload['distance'], 42);

    await repository.saveCardDisplay(
      'skill-running',
      CardDisplayConfig(
        primaryFieldId: 'date',
        secondaryFieldIds: const ['distance'],
      ),
      skill.renderSpec,
    );

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'GET /api/skills',
      'PATCH /api/skills/skill-running',
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
