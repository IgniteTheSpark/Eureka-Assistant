import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/assets/assets.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme_v2/asset/asset_card.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/asset/asset_list_page.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'Todo list exposes four counted tabs and keeps unscheduled last',
    (tester) async {
      final items = [
        AssetItem(
          id: 'open',
          skillName: 'todo',
          payload: const {'title': '整理灵感', 'status': 'pending'},
          createdAt: DateTime(2026, 7, 29, 12),
        ),
        AssetItem(
          id: 'evening',
          skillName: 'todo',
          payload: const {
            'title': '晚间复盘',
            'status': 'pending',
            'due_at': '2026-07-29T20:00:00+08:00',
          },
          createdAt: DateTime(2026, 7, 29, 11),
        ),
        AssetItem(
          id: 'morning',
          skillName: 'todo',
          payload: const {
            'title': '晨会',
            'status': 'pending',
            'due_at': '2026-07-29T09:00:00+08:00',
          },
          createdAt: DateTime(2026, 7, 29, 10),
        ),
        AssetItem(
          id: 'done',
          skillName: 'todo',
          payload: const {'title': '已完成', 'status': 'done'},
          createdAt: DateTime(2026, 7, 29, 9),
        ),
      ];

      await tester.pumpWidget(
        _host(
          ThemeV2AssetListPage.assets(
            meta: const SkillMeta('✓', '待办', 'gray', 'skill-todo'),
            skillName: 'todo',
            initialAssets: items,
            specs: const {
              'todo': RenderSpec(
                cardLayout: 'horizontal',
                icon: '✓',
                accentColor: 'gray',
                primaryField: 'title',
                secondaryField: 'due_at',
                schemaFields: ['title', 'due_at', 'status'],
              ),
            },
            autoLoad: false,
            today: () => DateTime(2026, 7, 29, 12),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('todo-filter-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-filter-today')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('todo-filter-completed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('todo-filter-unscheduled')),
        findsOneWidget,
      );
      expect(find.byType(ThemeV2AssetCard), findsNWidgets(4));
      expect(
        tester.getTopLeft(find.text('晨会')).dy,
        lessThan(tester.getTopLeft(find.text('整理灵感')).dy),
      );

      await tester.tap(find.byKey(const ValueKey('todo-filter-unscheduled')));
      await tester.pump();

      expect(find.text('整理灵感'), findsOneWidget);
      expect(find.byKey(const ValueKey('asset-record-morning')), findsNothing);
      expect(find.byKey(const ValueKey('asset-record-done')), findsNothing);
    },
  );

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
          return _jsonResponse(
            _assetDetailEnvelope(
              id: 'a1',
              skillName: 'notes',
              displayName: '随记',
              values: const {'title': '完整随记'},
              fields: const [('title', '标题')],
            ),
          );
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
      expect(find.text('设定目标'), findsNothing);
      expect(requests, ['GET /api/asset-details/asset/a1']);
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
        return _jsonResponse(_eventDetailEnvelope('e1'));
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
    expect(requests, ['GET /api/asset-details/event/e1']);
  });

  testWidgets('custom asset list exposes Card Display configuration', (
    tester,
  ) async {
    var configured = false;
    await tester.pumpWidget(
      _host(
        ThemeV2AssetListPage.assets(
          meta: const SkillMeta('🎾', '网球记录', 'gray', 'skill-tennis'),
          skillName: 'tennis',
          initialAssets: const [],
          specs: const {},
          autoLoad: false,
          onConfigureCard: () => configured = true,
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Card Display Settings'));
    expect(configured, isTrue);
  });

  testWidgets('loads a Theme V2 core asset list by user skill id', (
    tester,
  ) async {
    final requestedUris = <Uri>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requestedUris.add(request.url);
        if (request.url.path == '/api/skills') {
          return _jsonResponse({'detail': 'Not Found'}, statusCode: 404);
        }
        return _jsonResponse([
          {
            'id': 'core-note-1',
            'user_skill_id': 'core-notes',
            'payload': {'content': 'Theme V2 note one'},
            'effective_at': '2026-08-02T05:00:00Z',
            'created_at': '2026-08-02T05:00:00Z',
          },
          {
            'id': 'core-note-2',
            'user_skill_id': 'core-notes',
            'payload': {'content': 'Theme V2 note two'},
            'effective_at': '2026-08-02T04:00:00Z',
            'created_at': '2026-08-02T04:00:00Z',
          },
        ]);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetListPage.assets(
          meta: const SkillMeta('•', '随记', 'gray', 'core-notes'),
          skillName: 'notes',
          initialAssets: const [],
          specs: const {
            'notes': RenderSpec(
              cardLayout: 'horizontal',
              icon: '•',
              accentColor: 'gray',
              primaryField: 'content',
              schemaFields: ['content'],
            ),
          },
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final assetsRequest = requestedUris.singleWhere(
      (uri) => uri.path == '/api/assets',
    );
    expect(assetsRequest.queryParameters['user_skill_id'], 'core-notes');
    expect(find.text('Theme V2 note one'), findsOneWidget);
    expect(find.text('Theme V2 note two'), findsOneWidget);
    expect(find.text('还没有内容'), findsNothing);
  });

  testWidgets('updates a Theme V2 todo with the core PATCH contract', (
    tester,
  ) async {
    final methods = <String>[];
    Map<String, dynamic>? patchBody;
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        methods.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/skills') {
          return _jsonResponse({'detail': 'Not Found'}, statusCode: 404);
        }
        if (request.method == 'PATCH') {
          patchBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'id': 'core-todo',
            'user_skill_id': 'core-todo-skill',
            'payload': patchBody!['payload'],
            'effective_at': '2026-08-02T05:00:00Z',
            'created_at': '2026-08-02T05:00:00Z',
          });
        }
        return _jsonResponse([
          {
            'id': 'core-todo',
            'user_skill_id': 'core-todo-skill',
            'payload': {'title': '完成真机验收', 'status': 'pending'},
            'effective_at': '2026-08-02T05:00:00Z',
            'created_at': '2026-08-02T05:00:00Z',
          },
        ]);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetListPage.assets(
          meta: const SkillMeta('✓', '待办', 'gray', 'core-todo-skill'),
          skillName: 'todo',
          initialAssets: const [],
          specs: const {
            'todo': RenderSpec(
              cardLayout: 'horizontal',
              icon: '✓',
              accentColor: 'gray',
              primaryField: 'title',
              schemaFields: ['title', 'status'],
            ),
          },
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo-complete-core-todo')));
    await tester.pumpAndSettle();

    expect(methods, contains('PATCH /api/assets/core-todo'));
    expect(methods, isNot(contains('PUT /api/assets/core-todo')));
    expect(patchBody?['payload'], {'title': '完成真机验收', 'status': 'done'});
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
        if (request.url.path == '/api/asset-details/asset/a1') {
          return _jsonResponse(
            _assetDetailEnvelope(
              id: 'a1',
              skillName: 'tennis_match',
              displayName: '网球对局簿',
              values: const {'opponent': 'Alex'},
              fields: const [('opponent', '对手'), ('result', '赛果')],
            ),
          );
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

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _assetDetailEnvelope({
  required String id,
  required String skillName,
  required String displayName,
  required Map<String, dynamic> values,
  required List<(String, String)> fields,
}) => {
  'entity': {'kind': 'asset', 'id': id, 'version': 'version-1'},
  'skill': {
    'id': 'skill-$skillName',
    'machine_name': skillName,
    'display_name': displayName,
    'icon': skillName == 'notes' ? '✍️' : '🎾',
  },
  'fields': [
    for (var index = 0; index < fields.length; index++)
      {
        'id': fields[index].$1,
        'label': fields[index].$2,
        'type': 'string',
        'required': index == 0,
        'long': false,
        'order': index,
      },
  ],
  'values': values,
  'display': {
    'primary_field_id': fields.first.$1,
    'secondary_field_ids': [for (final field in fields.skip(1)) field.$1],
  },
  'source': {
    'kind': 'manual',
    'label': '手动创建',
    'session_id': null,
    'input_turn_id': null,
  },
  'capabilities': {'editable': true, 'deletable': true},
};

Map<String, dynamic> _eventDetailEnvelope(String id) => {
  'entity': {'kind': 'event', 'id': id, 'version': 'version-1'},
  'skill': {
    'id': null,
    'machine_name': 'event',
    'display_name': '事件',
    'icon': '📅',
  },
  'fields': [
    {
      'id': 'title',
      'label': '标题',
      'type': 'string',
      'required': true,
      'long': false,
      'order': 0,
    },
    {
      'id': 'start_at',
      'label': '开始',
      'type': 'datetime',
      'required': true,
      'long': false,
      'order': 1,
    },
    {
      'id': 'end_at',
      'label': '结束',
      'type': 'datetime',
      'required': false,
      'long': false,
      'order': 2,
    },
  ],
  'values': {
    'title': '设计评审',
    'start_at': '2026-07-28T15:00:00+08:00',
    'end_at': '2026-07-28T16:00:00+08:00',
  },
  'display': {
    'primary_field_id': 'title',
    'secondary_field_ids': ['start_at'],
  },
  'source': {
    'kind': 'manual',
    'label': '手动创建',
    'session_id': null,
    'input_turn_id': null,
  },
  'capabilities': {'editable': true, 'deletable': true},
};
