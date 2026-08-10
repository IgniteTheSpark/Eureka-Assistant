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
  testWidgets('todo create defaults deadline and exposes quick dates', (
    tester,
  ) async {
    late http.Request request;
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode({'id': 'todo-1'}), 200);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2AssetEditPage(
          reference: const AssetEntityRef(
            kind: AssetEntityKind.asset,
            id: 'new:todo',
          ),
          initialValues: const {},
          mode: AssetEditMode.create,
          skillName: 'todo',
          userSkillId: 'skill-todo',
          displayName: '待办',
          spec: synthesizeSpec('todo'),
          now: () => DateTime(2026, 8, 8, 18, 1),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo-deadline-field')), findsOneWidget);
    expect(find.text('2026年8月9日 18:00'), findsOneWidget);
    expect(find.text('截止时间'), findsOneWidget);
    expect(find.text('截止时间 *'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('todo-deadline-today')));
    await tester.pump();
    expect(find.text('2026年8月9日 18:00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo-deadline-tomorrow')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('asset-editor-title')),
      '提交方案',
    );
    await tester.tap(find.byKey(const ValueKey('asset-editor-save')));
    await tester.pumpAndSettle();

    expect(jsonDecode(request.body), {
      'user_skill_id': 'skill-todo',
      'payload': {'title': '提交方案', 'due_date': '2026-08-09T18:00:00+08:00'},
    });
  });

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
          userSkillId: 'skill-notes',
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
      'user_skill_id': 'skill-notes',
      'payload': {'title': '测试随记', 'body': '# 正文\n\n- 条目'},
    });
  });

  testWidgets('create loads its schema from the Theme V2 user-skill API', (
    tester,
  ) async {
    final requestedPaths = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response(
          jsonEncode([
            {
              'id': 'skill-notes',
              'machine_name': 'notes',
              'display_name': '随记',
              'schema': {
                'type': 'object',
                'properties': {
                  'title': {'type': 'string', 'title': '标题'},
                },
                'required': ['title'],
              },
              'render_spec': {'icon': '✍️', 'primary_field': 'title'},
            },
          ]),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

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
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPaths, ['/api/user-skills']);
    expect(find.byKey(const ValueKey('asset-editor-title')), findsOneWidget);
  });
}
