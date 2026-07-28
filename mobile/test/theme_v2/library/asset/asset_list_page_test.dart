import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/assets/assets.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/asset/asset_list_page.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('asset list orders and labels records by effectiveAt', (
    tester,
  ) async {
    final createdNewest = AssetItem(
      id: 'created-newest',
      skillName: 'tennis_match',
      payload: const {'opponent': '较早发生'},
      createdAt: DateTime(2026, 7, 28),
      effectiveAt: DateTime(2026, 7, 2),
      userSkillId: 'skill-tennis',
    );
    final effectiveNewest = AssetItem(
      id: 'effective-newest',
      skillName: 'tennis_match',
      payload: const {'opponent': '较晚发生'},
      createdAt: DateTime(2026, 7, 20),
      effectiveAt: DateTime(2026, 7, 3),
      userSkillId: 'skill-tennis',
    );

    await tester.pumpWidget(
      _host(
        ThemeV2AssetListPage.assets(
          meta: const SkillMeta('🎾', '网球对局簿', 'purple', 'skill-tennis'),
          skillName: 'tennis_match',
          initialAssets: [createdNewest, effectiveNewest],
          specs: const {
            'tennis_match': RenderSpec(
              cardLayout: 'horizontal',
              icon: '🎾',
              accentColor: 'purple',
              primaryField: 'opponent',
              schemaFields: ['opponent'],
              fieldLabels: {'opponent': '对手'},
            ),
          },
          autoLoad: false,
        ),
      ),
    );

    final first = tester.getTopLeft(find.text('较晚发生')).dy;
    final second = tester.getTopLeft(find.text('较早发生')).dy;
    expect(first, lessThan(second));
    expect(find.text('07.03'), findsOneWidget);
    expect(find.text('07.02'), findsOneWidget);
  });

  testWidgets(
    'asset row opens the shared bottom sheet with its skill binding',
    (tester) async {
      final requests = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return _jsonResponse({
            'asset': {
              'id': 'a1',
              'user_skill_name': 'notes',
              'payload': {'title': '完整随记'},
            },
          });
        }),
      );
      addTearDown(api.close);
      final item = AssetItem(
        id: 'a1',
        skillName: 'notes',
        payload: const {'title': '随记'},
        createdAt: DateTime(2026, 7, 28),
        userSkillId: 'skill-notes',
      );

      await tester.pumpWidget(
        _host(
          ThemeV2AssetListPage.assets(
            meta: const SkillMeta('✍️', '随记', 'amber', 'skill-notes'),
            skillName: 'notes',
            initialAssets: [item],
            specs: const {
              'notes': RenderSpec(
                cardLayout: 'horizontal',
                icon: '✍️',
                accentColor: 'amber',
                primaryField: 'title',
                schemaFields: ['title'],
              ),
            },
            api: api,
            autoLoad: false,
          ),
        ),
      );

      await tester.tap(find.text('随记').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('theme-v2-asset-sheet')),
        findsOneWidget,
      );
      expect(find.text('设定目标'), findsOneWidget);
      expect(requests, ['GET /api/assets/a1']);
    },
  );

  testWidgets('entity list uses the entity endpoint and same sheet chrome', (
    tester,
  ) async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return _jsonResponse({
          'event': {
            'event_id': 'e1',
            'title': '设计评审',
            'start_at': '2026-07-28T15:00:00+08:00',
            'end_at': '2026-07-28T16:00:00+08:00',
          },
        });
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetListPage.entities(
          title: '事件档案',
          cardType: 'event',
          initialEntities: const [
            {
              'event_id': 'e1',
              'title': '设计评审',
              'start_at': '2026-07-28T15:00:00+08:00',
              'end_at': '2026-07-28T16:00:00+08:00',
            },
          ],
          api: api,
          autoLoad: false,
        ),
      ),
    );

    await tester.tap(find.text('设计评审'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('theme-v2-asset-sheet')), findsOneWidget);
    expect(requests, ['GET /api/events/e1']);
  });

  testWidgets('custom asset list refreshes its schema before editing', (
    tester,
  ) async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/skills') {
          return _jsonResponse({
            'skills': [
              {
                'name': 'tennis_match',
                'render_spec': {
                  'card_layout': 'horizontal',
                  'icon': '🎾',
                  'accent_color': 'purple',
                  'primary_field': 'opponent',
                },
                'payload_schema': {
                  'opponent': {
                    'label': '对手',
                    'type': 'string',
                    'required': true,
                  },
                  'result': {'label': '赛果', 'type': 'string'},
                },
              },
            ],
          });
        }
        if (request.url.path == '/api/assets/a1') {
          return _jsonResponse({
            'asset': {
              'id': 'a1',
              'user_skill_id': 'skill-tennis',
              'user_skill_name': 'tennis_match',
              'payload': {'opponent': 'Alex'},
            },
          });
        }
        return _jsonResponse({
          'assets': [
            {
              'id': 'a1',
              'user_skill_id': 'skill-tennis',
              'user_skill_name': 'tennis_match',
              'payload': {'opponent': 'Alex'},
              'created_at': '2026-07-28T09:00:00+08:00',
            },
          ],
        });
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetListPage.assets(
          meta: const SkillMeta('🎾', '网球对局簿', 'purple', 'skill-tennis'),
          skillName: 'tennis_match',
          initialAssets: const [],
          specs: const {},
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-edit')));
    await tester.pumpAndSettle();

    expect(requests, contains('GET /api/skills'));
    expect(find.byKey(const ValueKey('asset-editor-result')), findsOneWidget);
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData.light(),
  home: Theme(
    data: buildThemeV2Theme(Brightness.light),
    child: Scaffold(body: SafeArea(child: child)),
  ),
);

http.Response _jsonResponse(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
