import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pages/create_asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('manual create definitions pin canonical built-in icons', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'skills': [
              {
                'name': 'expense',
                'display_name': '消费',
                'render_spec': {'icon': '🍔'},
              },
              {
                'name': 'contact',
                'display_name': '联系人',
                'render_spec': {'icon': '🪪'},
              },
              {
                'name': 'running',
                'display_name': '跑步',
                'render_spec': {'icon': '🏃'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    final skills = await fetchSkillDefs(api);
    expect(
      {for (final skill in skills) skill.name: skill.icon},
      {'expense': '💳', 'contact': '👤', 'running': '🏃'},
    );
  });
}
