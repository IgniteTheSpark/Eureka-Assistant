import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/asset/asset_detail_presentation.dart';
import 'package:eureka/theme_v2/library/asset/asset_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('half detail is 576 high and keeps source above sticky actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 960);
    addTearDown(tester.view.reset);
    final controller = AssetDetailController(
      data: buildCard(
        payload: const {'title': '随记', 'body': '正文'},
        spec: _spec,
        displayName: 'notes',
      ),
      payload: const {'title': '随记', 'body': '正文'},
      cardType: 'notes',
      assetId: null,
      userSkillId: 'skill-notes',
      sessionId: 'session-source',
      spec: _spec,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('theme-v2-asset-sheet'))).height,
      576,
    );
    final source = find.byKey(const ValueKey('asset-detail-source'));
    final actions = find.byKey(const ValueKey('asset-detail-actions'));
    expect(source, findsOneWidget);
    expect(actions, findsOneWidget);
    expect(
      tester.getBottomLeft(source).dy,
      lessThan(tester.getTopLeft(actions).dy),
    );
  });

  testWidgets(
    'editing expands in place with one hydration, draft and scroll position',
    (tester) async {
      var hydrationRequests = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          hydrationRequests++;
          return http.Response(
            jsonEncode({
              'asset': {
                'id': 'asset-1',
                'user_skill_name': 'notes',
                'payload': {
                  'title': '服务端标题',
                  'body': '服务端长文',
                  for (var i = 0; i < 12; i++) 'field_$i': 'value $i',
                },
              },
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final controller = AssetDetailController(
        api: api,
        data: buildCard(
          payload: const {'title': '卡片标题'},
          spec: _spec,
          displayName: 'notes',
        ),
        payload: const {'title': '卡片标题'},
        cardType: 'notes',
        assetId: 'asset-1',
        userSkillId: 'skill-1',
        spec: _spec,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('theme-v2-asset-sheet')),
        findsOneWidget,
      );
      expect(hydrationRequests, 1);
      expect(find.text('设定目标'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('asset-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('asset-editor-title')),
        '未保存草稿',
      );
      await tester.pump();
      controller.scrollController.jumpTo(180);
      final before = controller.scrollController.offset;

      expect(
        find.byKey(const ValueKey('theme-v2-asset-full-page')),
        findsOneWidget,
      );
      expect(controller.editing, isTrue);
      expect(controller.draft.controllerFor('title').text, '未保存草稿');
      expect(controller.scrollController.offset, closeTo(before, 0.5));
      expect(hydrationRequests, 1);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('asset-detail-close')));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '继续编辑'));
      await tester.pumpAndSettle();
      expect(controller.editing, isTrue);
      expect(controller.draft.controllerFor('title').text, '未保存草稿');
    },
  );

  testWidgets('detail exposes delete and entity mutations use typed paths', (
    tester,
  ) async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'DELETE') return http.Response('', 200);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'event': {'event_id': 'event-1', 'title': '评审'},
            }),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    final controller = AssetDetailController(
      api: api,
      data: buildCard(
        payload: const {'title': '评审'},
        spec: synthesizeSpec('event'),
        displayName: 'event',
      ),
      payload: const {'title': '评审'},
      cardType: 'event',
      assetId: 'event-1',
      userSkillId: null,
      spec: synthesizeSpec('event'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('asset-detail-delete')), findsOneWidget);

    await controller.saveDraft(const {'title': '新标题'});
    await tester.tap(find.byKey(const ValueKey('asset-detail-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(requests, [
      'GET /api/events/event-1',
      'PUT /api/events/event-1',
      'DELETE /api/events/event-1',
    ]);
  });
}

const _spec = RenderSpec(
  cardLayout: 'horizontal',
  icon: '✍️',
  accentColor: 'amber',
  primaryField: 'title',
  schemaFields: [
    'title',
    'body',
    'field_0',
    'field_1',
    'field_2',
    'field_3',
    'field_4',
    'field_5',
    'field_6',
    'field_7',
    'field_8',
    'field_9',
    'field_10',
    'field_11',
  ],
  fieldLabels: {'title': '标题', 'body': '正文'},
  longFields: {'body'},
  requiredFields: {'title'},
);

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData.light(),
  home: Theme(
    data: buildThemeV2Theme(Brightness.light),
    child: Scaffold(body: SafeArea(child: child)),
  ),
);
