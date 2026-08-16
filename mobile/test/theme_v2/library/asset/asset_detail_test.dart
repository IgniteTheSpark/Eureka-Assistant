import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pages/report_viewer_page.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_model.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/asset/asset_detail_presentation.dart';
import 'package:eureka/theme_v2/library/asset/asset_detail_sheet.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
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

  testWidgets('a deliberate slow upward drag expands the detail sheet', (
    tester,
  ) async {
    final model = AssetDetailModel.fromJson(_assetEnvelope());
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byKey(const ValueKey('asset-detail-drag-region')),
      const Offset(0, -72),
      const Duration(milliseconds: 900),
    );
    await tester.pumpAndSettle();

    expect(controller.presentation, AssetDetailPresentationKind.fullPage);
    expect(
      find.byKey(const ValueKey('theme-v2-asset-full-page')),
      findsOneWidget,
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

  testWidgets(
    'Flash source opens its exact input turn and preserves detail state on back',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 960);
      addTearDown(tester.view.reset);
      final model = AssetDetailModel.fromJson(
        _assetEnvelope(manyFields: true, flashSource: true),
      );
      final controller = AssetDetailController(
        repository: _FakeRepository(model),
        ref: model.ref,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
      await tester.pumpAndSettle();
      controller.expand();
      await tester.pumpAndSettle();
      controller.scrollController.jumpTo(
        controller.scrollController.position.maxScrollExtent / 2,
      );
      final offset = controller.scrollController.offset;
      expect(offset, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('asset-detail-source')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final session = tester.widget<ThemeV2SessionPage>(
        find.byType(ThemeV2SessionPage),
      );
      expect(session.boundSessionId, 'session-1');
      expect(session.focusedInputTurnId, 'turn-2');

      Navigator.of(tester.element(find.byType(ThemeV2SessionPage))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(controller.presentation, AssetDetailPresentationKind.fullPage);
      expect(controller.scrollController.offset, closeTo(offset, 0.5));
    },
  );

  testWidgets('manual source is visible but has no navigation semantics', (
    tester,
  ) async {
    final model = AssetDetailModel.fromJson(_assetEnvelope());
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
    await tester.pumpAndSettle();

    expect(find.text('手动创建'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('asset-detail-source')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('report source opens the original report with Theme V2 actions', (
    tester,
  ) async {
    final observer = _ReportRouteObserver();
    final requested = <String>[];
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        requested.add('${request.method} ${request.url.path}');
        return _jsonResponse({
          'id': 'report-1',
          'title': '月度复盘',
          'html': '<html><body>月度复盘</body></html>',
          'spec': {'palette': 'pal-ink'},
        });
      }),
    );
    addTearDown(api.close);
    final json = _assetEnvelope();
    json['source'] = {
      'kind': 'report',
      'label': '来自报告《月度复盘》',
      'session_id': null,
      'input_turn_id': null,
      'report_id': 'report-1',
    };
    final model = AssetDetailModel.fromJson(json);
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetDetailSurface(controller, api: api),
        navigatorObservers: [observer],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-source')));
    final route = await tester.runAsync(() => observer.reportRoute.future);
    final page = route!.builder(route.navigator!.context) as ReportViewerPage;

    expect(page.reportId, 'report-1');
    expect(page.enableLegacyEnhancements, isFalse);
    expect(page.enableThemeV2Actions, isTrue);
    expect(page.themeV2Palette, 'pal-ink');
    expect(requested, ['GET /api/reports/report-1']);
    route.navigator!.pop();
    await tester.pump();
  });

  testWidgets('missing source report stays on detail and explains deletion', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((_) async => http.Response('not found', 404)),
    );
    addTearDown(api.close);
    final json = _assetEnvelope();
    json['source'] = {
      'kind': 'report',
      'label': '来自报告《已删除报告》',
      'session_id': null,
      'input_turn_id': null,
      'report_id': 'deleted-report',
    };
    final model = AssetDetailModel.fromJson(json);
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(ThemeV2AssetDetailSurface(controller, api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-source')));
    await tester.pumpAndSettle();

    expect(find.byType(ThemeV2AssetDetailSurface), findsOneWidget);
    expect(find.byType(ReportViewerPage), findsNothing);
    expect(find.text('来源报告已不存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleted report provenance is visible without navigation', (
    tester,
  ) async {
    final json = _assetEnvelope();
    json['source'] = {
      'kind': 'report',
      'label': '来自报告《月度复盘》',
      'session_id': null,
      'input_turn_id': null,
      'report_id': null,
    };
    final model = AssetDetailModel.fromJson(json);
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
    await tester.pumpAndSettle();

    expect(find.text('来自报告《月度复盘》'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('asset-detail-source')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('event detail renders only its declared business fields', (
    tester,
  ) async {
    final model = AssetDetailModel.fromJson(_eventEnvelopeWithStorageFields());
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
    await tester.pumpAndSettle();

    expect(find.text('设计评审'), findsWidgets);
    expect(find.text('线上会议室'), findsOneWidget);
    expect(find.text('备注'), findsOneWidget);
    expect(find.text('scheduled'), findsNothing);
    expect(find.text('event-storage-id'), findsNothing);
    expect(find.text('2026-08-01T17:07:00Z'), findsNothing);
    expect(find.text('false'), findsNothing);
  });

  testWidgets('todo detail edits its pre-due reminder offsets', (tester) async {
    final model = AssetDetailModel.fromJson(_todoEnvelope());
    final repository = _RecordingRepository(model);
    final controller = AssetDetailController(
      repository: repository,
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(ThemeV2AssetDetailSurface(controller)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('asset-detail-reminders')),
      findsOneWidget,
    );
    expect(find.text('提前 15 分钟'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('asset-detail-reminders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-option-15')));
    await tester.tap(find.byKey(const ValueKey('reminder-option-60')));
    await tester.tap(find.byKey(const ValueKey('reminder-save')));
    await tester.pumpAndSettle();

    expect(repository.savedPatch, {
      'reminder_offsets_minutes': <int>[60],
    });
  });

  testWidgets('overdue todo replaces pre-due reminders with snooze actions', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 14, 10, 30);
    DateTime? snoozedUntil;
    var dismissed = false;
    final model = AssetDetailModel.fromJson(_todoEnvelope());
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetDetailSurface(
          controller,
          overdueReminder: RekaOverdueReminderContext(
            now: () => now,
            onSnooze: (value) async => snoozedUntil = value,
            onDismiss: () async => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-detail-reminders')), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-detail-overdue-reminder')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('overdue-snooze-60')));
    await tester.pump();
    expect(snoozedUntil, now.add(const Duration(hours: 1)));

    await tester.tap(find.byKey(const ValueKey('overdue-dismiss')));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('completed todo hides reminder and overdue snooze controls', (
    tester,
  ) async {
    final json = _todoEnvelope();
    (json['values'] as Map<String, dynamic>)['status'] = 'done';
    final model = AssetDetailModel.fromJson(json);
    final controller = AssetDetailController(
      repository: _FakeRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        ThemeV2AssetDetailSurface(
          controller,
          overdueReminder: RekaOverdueReminderContext(
            now: () => DateTime(2026, 8, 14, 10, 30),
            onSnooze: (_) async {},
            onDismiss: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('asset-detail-reminders')), findsNothing);
    expect(
      find.byKey(const ValueKey('asset-detail-overdue-reminder')),
      findsNothing,
    );
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

class _RecordingRepository implements AssetDetailRepository {
  _RecordingRepository(this.model);

  final AssetDetailModel model;
  Map<String, dynamic>? savedPatch;

  @override
  Future<AssetDetailModel> load(AssetEntityRef ref) async => model;

  @override
  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  ) async {
    savedPatch = Map<String, dynamic>.from(valuesPatch);
    return current;
  }

  @override
  Future<void> delete(AssetEntityRef ref) async {}
}

Map<String, dynamic> _assetEnvelope({
  bool manyFields = false,
  bool flashSource = false,
}) {
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
      'kind': flashSource ? 'flash' : 'manual',
      'label': flashSource ? '来自闪念' : '手动创建',
      'session_id': flashSource ? 'session-1' : null,
      'input_turn_id': flashSource ? 'turn-2' : null,
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
    'icon': '📅',
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

Map<String, dynamic> _todoEnvelope() => {
  'entity': {'kind': 'asset', 'id': 'todo-1', 'version': 'version-1'},
  'skill': {
    'id': 'skill-todo',
    'machine_name': 'todo',
    'display_name': '待办',
    'icon': '☑',
  },
  'fields': [
    _field('title', '标题', order: 0, required: true),
    _field('due_date', '截止时间', order: 1),
  ],
  'values': {
    'title': '提交方案',
    'due_date': '2026-08-14T09:00:00+08:00',
    'status': 'pending',
    'reminder_offsets_minutes': <int>[15],
  },
  'display': {
    'primary_field_id': 'title',
    'secondary_field_ids': ['due_date'],
  },
  'source': {
    'kind': 'manual',
    'label': '手动创建',
    'session_id': null,
    'input_turn_id': null,
  },
  'capabilities': {'editable': true, 'deletable': true},
};

Map<String, dynamic> _eventEnvelopeWithStorageFields() => {
  'entity': {'kind': 'event', 'id': 'event-1', 'version': 'version-1'},
  'skill': {
    'id': null,
    'machine_name': 'event',
    'display_name': '事件',
    'icon': '📅',
  },
  'fields': [
    _field('title', '标题', order: 0, required: true),
    _field('start_at', '开始', order: 1),
    _field('end_at', '结束', order: 2),
    _field('location', '地点', order: 3),
    _field('description', '备注', order: 4, long: true),
  ],
  'values': {
    'id': 'event-storage-id',
    'title': '设计评审',
    'start_at': '2026-08-02T01:00:00Z',
    'end_at': '2026-08-02T02:00:00Z',
    'location': '线上会议室',
    'description': '讨论 Theme V2',
    'all_day': false,
    'status': 'scheduled',
    'created_at': '2026-08-01T17:07:00Z',
    'updated_at': '2026-08-01T17:08:00Z',
  },
  'display': {
    'primary_field_id': 'title',
    'secondary_field_ids': ['start_at', 'end_at', 'location', 'description'],
  },
  'source': {
    'kind': 'manual',
    'label': '手动创建',
    'session_id': null,
    'input_turn_id': null,
  },
  'capabilities': {'editable': false, 'deletable': true},
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

class _ReportRouteObserver extends NavigatorObserver {
  final reportRoute = Completer<MaterialPageRoute<void>>();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null &&
        route is MaterialPageRoute<void> &&
        !reportRoute.isCompleted) {
      reportRoute.complete(route);
    }
  }
}

Widget _host(
  Widget child, {
  List<NavigatorObserver> navigatorObservers = const [],
}) => MaterialApp(
  navigatorObservers: navigatorObservers,
  theme: ThemeData.light(),
  home: Theme(
    data: buildThemeV2Theme(Brightness.light),
    child: Scaffold(body: SafeArea(child: child)),
  ),
);
