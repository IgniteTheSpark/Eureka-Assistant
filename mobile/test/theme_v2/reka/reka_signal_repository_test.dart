import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/reka/reka_signal.dart';
import 'package:eureka/theme_v2/reka/reka_signal_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RekaSignal', () {
    test('parses the stable overdue contract and advertised actions', () {
      final signal = RekaSignal.tryParse({
        'id': 'signal-overdue',
        'natural_key': 'overdue:todo-1:2026-08-08T06:00:00Z',
        'kind': 'overdue',
        'title': '参加面试 已到截止时间',
        'body': '这项待办仍未完成，可以现在处理或调整时间。',
        'target': {'type': 'asset', 'id': 'todo-1'},
        'actions': ['open', 'snooze', 'dismiss', 'unknown'],
        'delivered_at': '2026-08-10T03:57:32Z',
        'expires_at': '2026-08-10T22:00:00Z',
      });

      expect(signal, isNotNull);
      expect(signal!.kind, RekaSignalKind.overdue);
      expect(signal.target.type, RekaSignalTargetType.asset);
      expect(signal.target.id, 'todo-1');
      expect(signal.actions, [
        RekaSignalAction.open,
        RekaSignalAction.snooze,
        RekaSignalAction.dismiss,
      ]);
      expect(signal.expiresAt, DateTime.parse('2026-08-10T22:00:00Z'));
    });

    test('rejects unknown kinds and malformed targets', () {
      expect(
        RekaSignal.tryParse({
          'id': 'report-receipt',
          'kind': 'report_failed',
          'title': '报告生成失败',
          'target': {'type': 'report', 'id': 'report-1'},
          'actions': ['open'],
          'delivered_at': '2026-08-10T03:57:32Z',
        }),
        isNull,
      );
      expect(
        RekaSignal.tryParse({
          'id': 'broken',
          'kind': 'rhythm_gap',
          'title': '消费还没有记录',
          'target': {'type': 'skill', 'id': ''},
          'actions': ['open'],
          'delivered_at': '2026-08-10T03:57:32Z',
        }),
        isNull,
      );
    });

    test('parses a report offer backed by a trigger execution', () {
      final signal = RekaSignal.tryParse({
        'id': 'report-offer',
        'natural_key': 'report:execution-1:opportunity',
        'kind': 'report',
        'title': '为球队建设会议准备会前调研',
        'body': '会议即将开始，可以先确认调研范围。',
        'target': {'type': 'trigger_execution', 'id': 'execution-1'},
        'actions': ['open', 'dismiss'],
        'delivered_at': '2026-08-10T03:57:32Z',
        'phase': 'opportunity',
        'chain_id': 'execution-1',
        'evidence': {'event_title': '球队建设会议'},
      });

      expect(signal, isNotNull);
      expect(signal!.kind, RekaSignalKind.report);
      expect(signal.target.type, RekaSignalTargetType.triggerExecution);
      expect(signal.target.id, 'execution-1');
      expect(signal.reportPhase, RekaReportPhase.opportunity);
      expect(signal.chainId, 'execution-1');
      expect(signal.evidence, {'event_title': '球队建设会议'});
    });

    test('parses plan-ready and report-ready targets', () {
      final plan = RekaSignal.tryParse({
        'id': 'plan-ready',
        'natural_key': 'report:execution-1:plan_ready',
        'kind': 'report',
        'title': '报告方案已准备好',
        'body': '可以查看方案。',
        'target': {'type': 'report_run', 'id': 'run-1'},
        'actions': ['open', 'dismiss'],
        'delivered_at': '2026-08-10T03:57:32Z',
        'phase': 'plan_ready',
        'chain_id': 'execution-1',
        'report_run_id': 'run-1',
      });
      final ready = RekaSignal.tryParse({
        'id': 'report-ready',
        'natural_key': 'report:execution-1:report_ready',
        'kind': 'report',
        'title': '报告已生成',
        'body': '产品路线研究',
        'target': {'type': 'report', 'id': 'report-1'},
        'actions': ['open', 'dismiss'],
        'delivered_at': '2026-08-10T03:57:32Z',
        'phase': 'report_ready',
        'chain_id': 'execution-1',
        'report_run_id': 'run-1',
        'report_id': 'report-1',
      });

      expect(plan!.reportPhase, RekaReportPhase.planReady);
      expect(plan.target.type, RekaSignalTargetType.reportRun);
      expect(plan.reportRunId, 'run-1');
      expect(ready!.reportPhase, RekaReportPhase.reportReady);
      expect(ready.target.type, RekaSignalTargetType.report);
      expect(ready.reportId, 'report-1');
    });

    test('keeps a valid signal when a future phase or action is unknown', () {
      final signal = RekaSignal.tryParse({
        'id': 'future-report-phase',
        'natural_key': 'report:execution-1:future',
        'kind': 'report',
        'title': '新的报告阶段',
        'body': '',
        'target': {'type': 'report_run', 'id': 'run-1'},
        'actions': ['open', 'future_action'],
        'delivered_at': '2026-08-10T03:57:32Z',
        'phase': 'future_phase',
      });

      expect(signal, isNotNull);
      expect(signal!.reportPhase, isNull);
      expect(signal.actions, [RekaSignalAction.open]);
    });
  });

  group('ApiRekaSignalRepository', () {
    test(
      'loads signals with timezone and preserves partial failures',
      () async {
        late Uri requested;
        final api = _api((request) async {
          requested = request.url;
          return _json({
            'ok': true,
            'signals': [
              {
                'id': 'signal-rhythm',
                'natural_key': 'rhythm:expense:daily:any:2026-08-10',
                'kind': 'rhythm_gap',
                'title': '消费还没有记录',
                'body': '你通常会在今天记录，可以现在补上一笔。',
                'target': {'type': 'skill', 'id': 'expense'},
                'actions': ['open', 'dismiss'],
                'delivered_at': '2026-08-10T13:00:00Z',
                'expires_at': '2026-08-11T00:00:00Z',
              },
              {'id': 'malformed'},
            ],
            'partial_failures': ['overdue'],
            'generated_at': '2026-08-10T13:00:00Z',
          });
        });
        addTearDown(api.close);

        final result = await ApiRekaSignalRepository(
          api,
        ).load(timezoneName: 'Asia/Shanghai');

        expect(requested.path, '/api/reka/signals');
        expect(requested.queryParameters, {'timezone': 'Asia/Shanghai'});
        expect(result.signals.single.id, 'signal-rhythm');
        expect(result.signals.single.kind, RekaSignalKind.rhythmGap);
        expect(result.partialFailures, ['overdue']);
        expect(result.generatedAt, DateTime.parse('2026-08-10T13:00:00Z'));
      },
    );

    test(
      'dismisses one signal through its persisted lifecycle endpoint',
      () async {
        late http.Request requested;
        final api = _api((request) async {
          requested = request;
          return _json({'ok': true, 'status': 'dismissed'});
        });
        addTearDown(api.close);

        await ApiRekaSignalRepository(api).dismiss('signal-1');

        expect(requested.method, 'POST');
        expect(requested.url.path, '/api/reka/signals/signal-1/dismiss');
        expect(jsonDecode(requested.body), isEmpty);
      },
    );

    test('snoozes one overdue signal until a concrete UTC timestamp', () async {
      late http.Request requested;
      final api = _api((request) async {
        requested = request;
        return _json({
          'ok': true,
          'status': 'delivered',
          'remind_again_at': '2026-08-10T10:15:00Z',
        });
      });
      addTearDown(api.close);

      await ApiRekaSignalRepository(
        api,
      ).snooze('signal-1', DateTime.parse('2026-08-10T18:15:00+08:00'));

      expect(requested.method, 'POST');
      expect(requested.url.path, '/api/reka/signals/signal-1/snooze');
      expect(jsonDecode(requested.body), {
        'remind_again_at': '2026-08-10T10:15:00Z',
      });
    });

    test(
      'completes an overdue target through the canonical asset endpoint',
      () async {
        late http.Request requested;
        final api = _api((request) async {
          requested = request;
          return _json({
            'id': 'todo-1',
            'payload': {'status': 'done'},
          });
        });
        addTearDown(api.close);

        await ApiRekaSignalRepository(api).completeTodo('todo-1');

        expect(requested.method, 'PUT');
        expect(requested.url.path, '/api/assets/todo-1');
        expect(jsonDecode(requested.body), {
          'payload_patch': {'status': 'done'},
        });
      },
    );
  });
}

ApiClient _api(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      client: MockClient(handler),
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
    );

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json'},
);
