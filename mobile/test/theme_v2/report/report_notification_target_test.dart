import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/report/report_notification_target.dart';
import 'package:eureka/theme_v2/report/report_run_controller.dart';
import 'package:eureka/theme_v2/report/report_run_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('report-start notification resolves to a trigger report run page', () {
    const link = 'report-start:execution-123:2';

    expect(reportExecutionIdFromLink(link), 'execution-123');
    final page = reportNotificationTargetPage(link);
    expect(page, isA<ReportRunPage>());
    expect((page as ReportRunPage).triggerExecutionId, 'execution-123');
  });

  test('malformed report-start link is not actionable', () {
    expect(reportExecutionIdFromLink('report-start::1'), isNull);
    expect(reportExecutionIdFromLink('report:abc'), isNull);
  });

  test('report plan-ready notification reopens the existing run', () {
    const link = 'report-run:run-123';

    expect(reportRunIdFromLink(link), 'run-123');
    final page = reportNotificationTargetPage(link);
    expect(page, isA<ReportRunPage>());
    expect((page as ReportRunPage).runId, 'run-123');
  });

  test(
    'dismissing report availability updates trigger before notification',
    () async {
      final requested = <String>[];
      final api = ApiClient(
        baseUrl: 'http://test',
        enableLogging: false,
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url.path}');
          return _json({'ok': true});
        }),
      );
      addTearDown(api.close);

      await dismissReportAvailableNotification(
        api,
        notificationId: 'notification-1',
        link: 'report-start:execution-123:2',
      );

      expect(requested, [
        'POST /api/trigger-executions/execution-123/dismiss',
        'DELETE /api/notifications/notification-1',
      ]);
    },
  );

  test(
    'trigger notification creates a run and starts the selected plan',
    () async {
      final requested = <String>[];
      final api = ApiClient(
        baseUrl: 'http://test',
        enableLogging: false,
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/report-generation-runs') {
            expect(jsonDecode(request.body), {
              'origin': 'trigger',
              'trigger_execution_id': 'execution-123',
            });
            return _json({
              'id': 'run-1',
              'state': 'awaiting_selection',
              'plan_options': [
                {
                  'id': 'option-1',
                  'recommended': true,
                  'title': '会前调研',
                  'summary': '调研参会人与公司背景',
                },
              ],
            });
          }
          if (request.url.path ==
              '/api/report-generation-runs/run-1/generate') {
            expect(jsonDecode(request.body), {
              'selected_option_id': 'option-1',
            });
            return _json({'id': 'run-1', 'state': 'generating'});
          }
          return http.Response('not found', 404);
        }),
      );
      final controller = ReportRunController(api: api, autoPoll: false);
      addTearDown(() {
        controller.dispose();
        api.close();
      });

      await controller.startFromTrigger('execution-123');
      expect(controller.state, 'awaiting_selection');
      expect(controller.selectedOptionId, 'option-1');

      await controller.generate();
      expect(controller.state, 'generating');
      expect(requested, [
        'POST /api/report-generation-runs',
        'POST /api/report-generation-runs/run-1/generate',
      ]);
    },
  );

  test('clarification answers are submitted before planning resumes', () async {
    final requested = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((request) async {
        requested.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/report-generation-runs') {
          return _json({
            'id': 'run-clarify',
            'state': 'awaiting_selection',
            'pending_decision': {
              'type': 'clarification',
              'questions': [
                {
                  'id': 'focus',
                  'question': '重点关注什么？',
                  'options': ['公司背景', '参会人'],
                  'required': true,
                },
              ],
            },
            'plan_options': const [],
          });
        }
        if (request.url.path ==
            '/api/report-generation-runs/run-clarify/decision') {
          expect(jsonDecode(request.body), {
            'answers': {'focus': '公司背景'},
          });
          return _json({'id': 'run-clarify', 'state': 'planning'});
        }
        return http.Response('not found', 404);
      }),
    );
    final controller = ReportRunController(api: api, autoPoll: false);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.startFromTrigger('execution-clarify');
    expect(controller.needsClarification, isTrue);
    expect(controller.clarificationQuestions.single['id'], 'focus');
    controller.answerQuestion('focus', '公司背景');
    expect(controller.canSubmitClarification, isTrue);

    await controller.submitClarification();

    expect(controller.state, 'planning');
    expect(requested, [
      'POST /api/report-generation-runs',
      'POST /api/report-generation-runs/run-clarify/decision',
    ]);
  });
}

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
