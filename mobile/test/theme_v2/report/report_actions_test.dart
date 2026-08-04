import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/report/report_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('controller accepts a report with no suggested actions', () async {
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((_) async => _json({'actions': const []})),
    );
    final controller = ReportActionsController(api: api);
    addTearDown(controller.dispose);

    await controller.load('report-empty');

    expect(controller.actions, isEmpty);
    expect(controller.pendingCount, 0);
    expect(controller.errorMessage, isNull);
  });

  test(
    'controller loads actions and creates one by stored action id',
    () async {
      final requested = <String>[];
      var createdCallbacks = 0;
      final api = ApiClient(
        baseUrl: 'https://reports.test',
        enableLogging: false,
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url.path}');
          if (request.method == 'GET') {
            return _json({
              'actions': [
                {
                  'id': 'action-1',
                  'title': '准备访谈问题',
                  'due_at': '2026-08-10T01:00:00Z',
                  'created': false,
                  'todo_asset_id': null,
                },
              ],
            });
          }
          return _json({
            'id': 'action-1',
            'title': '准备访谈问题',
            'due_at': '2026-08-10T01:00:00Z',
            'created': true,
            'todo_asset_id': 'asset-1',
          });
        }),
      );
      final controller = ReportActionsController(
        api: api,
        onTodoCreated: () => createdCallbacks++,
      );
      addTearDown(controller.dispose);

      await controller.load('report-1');
      final added = await controller.add('report-1', 'action-1');

      expect(added, isTrue);
      expect(controller.actions.single.created, isTrue);
      expect(controller.actions.single.todoAssetId, 'asset-1');
      expect(controller.pendingCount, 0);
      expect(createdCallbacks, 1);
      expect(requested, [
        'GET /api/reports/report-1/actions',
        'POST /api/reports/report-1/actions/action-1',
      ]);
    },
  );

  test('empty load is stable and duplicate add is suppressed', () async {
    final postCompleter = Completer<http.Response>();
    var postCount = 0;
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return _json({
            'actions': [
              {
                'id': 'action-1',
                'title': '行动',
                'due_at': null,
                'created': false,
                'todo_asset_id': null,
              },
            ],
          });
        }
        postCount++;
        return postCompleter.future;
      }),
    );
    final controller = ReportActionsController(api: api);
    addTearDown(controller.dispose);
    await controller.load('report-1');

    final first = controller.add('report-1', 'action-1');
    final duplicate = await controller.add('report-1', 'action-1');
    expect(controller.isAdding('action-1'), isTrue);
    expect(duplicate, isFalse);
    postCompleter.complete(
      _json({
        'id': 'action-1',
        'title': '行动',
        'due_at': null,
        'created': false,
        'todo_asset_id': 'asset-1',
      }),
    );
    await first;

    expect(postCount, 1);
    expect(controller.actions.single.created, isTrue);
  });

  test('add all keeps successes when a later action fails', () async {
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return _json({
            'actions': [
              for (var index = 1; index <= 3; index++)
                {
                  'id': 'action-$index',
                  'title': '行动 $index',
                  'due_at': null,
                  'created': false,
                  'todo_asset_id': null,
                },
            ],
          });
        }
        if (request.url.path.endsWith('action-2')) {
          return http.Response('failed', 500);
        }
        final id = request.url.pathSegments.last;
        return _json({
          'id': id,
          'title': id == 'action-1' ? '行动 1' : '行动 3',
          'due_at': null,
          'created': true,
          'todo_asset_id': 'asset-$id',
        });
      }),
    );
    final controller = ReportActionsController(api: api);
    addTearDown(controller.dispose);
    await controller.load('report-1');

    await controller.addAll('report-1');

    expect(controller.actions.map((action) => action.created), [
      true,
      false,
      true,
    ]);
    expect(controller.errorMessage, '部分行动未能加入待办，请稍后重试');
  });

  testWidgets('tray keeps rows and buttons at least 48 logical pixels', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'https://reports.test',
      enableLogging: false,
      client: MockClient(
        (_) async => _json({
          'actions': [
            {
              'id': 'action-1',
              'title': '准备访谈问题',
              'due_at': '2026-08-10T01:00:00Z',
              'created': false,
              'todo_asset_id': null,
            },
            {
              'id': 'action-2',
              'title': '整理材料',
              'due_at': null,
              'created': false,
              'todo_asset_id': null,
            },
          ],
        }),
      ),
    );
    final controller = ReportActionsController(api: api);
    addTearDown(controller.dispose);
    await controller.load('report-1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportActionsTray(
            reportId: 'report-1',
            controller: controller,
            colors: EurekaColors.dark,
          ),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('report-action-action-1')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('report-action-add-action-1')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('全部加入待办'), findsOneWidget);
    expect(find.text('8月10日 09:00'), findsOneWidget);
  });
}

http.Response _json(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: const {'content-type': 'application/json'},
);
