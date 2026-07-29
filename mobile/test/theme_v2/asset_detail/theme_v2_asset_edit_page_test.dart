import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/asset_detail/theme_v2_asset_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('create posts strict schema values through the Theme V2 editor', (
    tester,
  ) async {
    late http.Request request;
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
    addTearDown(api.close);
    final spec = const RenderSpec(
      cardLayout: 'stacked',
      icon: '✍️',
      accentColor: 'gray',
      primaryField: 'title',
      fieldLabels: {'title': '标题', 'body': '正文'},
      schemaFields: ['title', 'body'],
      fieldTypes: {'title': 'string', 'body': 'string'},
      requiredFields: {'title'},
      longFields: {'body'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2AssetEditPage(
          reference: const AssetEntityRef(
            kind: AssetEntityKind.asset,
            id: 'new:notes',
          ),
          initialValues: const {},
          mode: AssetEditMode.create,
          skillName: 'notes',
          displayName: '随记',
          spec: spec,
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-title')),
      '测试随记',
    );
    await tester.enterText(
      find.byKey(const ValueKey('markdown-editor-input')),
      '# 正文\n\n- 条目',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(request.method, 'POST');
    expect(request.url.path, '/api/assets');
    expect(jsonDecode(request.body), {
      'user_skill_name': 'notes',
      'payload': {'title': '测试随记', 'body': '# 正文\n\n- 条目'},
      'domain': '',
    });
  });
}
