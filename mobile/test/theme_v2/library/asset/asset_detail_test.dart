import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_model.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
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
    final model = AssetDetailModel.fromJson(_assetEnvelope());
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
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
          return _jsonResponse(_assetEnvelope(manyFields: true));
        }),
      );
      addTearDown(api.close);
      final controller = AssetDetailController(
        repository: ApiAssetDetailRepository(api),
        ref: const AssetEntityRef(kind: AssetEntityKind.asset, id: 'asset-1'),
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

  testWidgets('detail saves through canonical path and deletes typed entity', (
    tester,
  ) async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'DELETE') return http.Response('', 200);
        final title = request.method == 'PUT' ? '新标题' : '评审';
        return _jsonResponse(_eventEnvelope(title: title));
      }),
    );
    addTearDown(api.close);
    final controller = AssetDetailController(
      repository: ApiAssetDetailRepository(api),
      ref: const AssetEntityRef(kind: AssetEntityKind.event, id: 'event-1'),
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
      'GET /api/asset-details/event/event-1',
      'PUT /api/asset-details/event/event-1',
      'DELETE /api/events/event-1',
    ]);
  });
}

class _FakeRepository implements AssetDetailRepository {
  const _FakeRepository(this.model);

  final AssetDetailModel model;

  @override
  Future<AssetDetailModel> load(AssetEntityRef ref) async => model;

  @override
  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  ) async => current;

  @override
  Future<void> delete(AssetEntityRef ref) async {}
}

Map<String, dynamic> _assetEnvelope({bool manyFields = false}) {
  final fields = <Map<String, dynamic>>[
    _field('title', '标题', order: 0, required: true),
    _field('body', '正文', order: 1, long: true),
    if (manyFields)
      for (var i = 0; i < 12; i++) _field('field_$i', '字段 $i', order: i + 2),
  ];
  return {
    'entity': {'kind': 'asset', 'id': 'asset-1', 'version': 'version-1'},
    'skill': {
      'id': 'skill-1',
      'machine_name': 'notes',
      'display_name': '随记',
      'icon': '✍️',
    },
    'fields': fields,
    'values': {
      'title': '服务端标题',
      'body': '服务端长文',
      if (manyFields)
        for (var i = 0; i < 12; i++) 'field_$i': 'value $i',
    },
    'display': {
      'primary_field_id': 'title',
      'secondary_field_ids': ['body'],
    },
    'source': {
      'kind': 'manual',
      'label': '手动创建',
      'session_id': null,
      'input_turn_id': null,
    },
    'capabilities': {'editable': true, 'deletable': true},
  };
}

Map<String, dynamic> _eventEnvelope({required String title}) => {
  'entity': {'kind': 'event', 'id': 'event-1', 'version': 'version-1'},
  'skill': {
    'id': null,
    'machine_name': 'event',
    'display_name': '事件',
    'icon': '▣',
  },
  'fields': [_field('title', '标题', order: 0, required: true)],
  'values': {'title': title},
  'display': {'primary_field_id': 'title', 'secondary_field_ids': <String>[]},
  'source': {
    'kind': 'manual',
    'label': '手动创建',
    'session_id': null,
    'input_turn_id': null,
  },
  'capabilities': {'editable': true, 'deletable': true},
};

Map<String, dynamic> _field(
  String id,
  String label, {
  required int order,
  bool required = false,
  bool long = false,
}) => {
  'id': id,
  'label': label,
  'type': 'string',
  'required': required,
  'long': long,
  'order': order,
};

http.Response _jsonResponse(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData.light(),
  home: Theme(
    data: buildThemeV2Theme(Brightness.light),
    child: Scaffold(body: SafeArea(child: child)),
  ),
);
