import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/report/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiReportRepository', () {
    test(
      'starts each overview source once before either response completes',
      () async {
        final runRequests = <Uri>[];
        final reportRequests = <Uri>[];
        final runsStarted = Completer<void>();
        final reportsStarted = Completer<void>();
        final releaseResponses = Completer<void>();
        final api = _api((request) async {
          switch (request.url.path) {
            case '/api/report-generation-runs':
              runRequests.add(request.url);
              runsStarted.complete();
              break;
            case '/api/reports':
              reportRequests.add(request.url);
              reportsStarted.complete();
              break;
            default:
              throw StateError('unexpected ${request.method} ${request.url}');
          }
          await releaseResponses.future;
          return _json([]);
        });
        addTearDown(api.close);

        final load = ApiReportRepository(api).loadOverview();
        try {
          await Future.wait([
            runsStarted.future,
            reportsStarted.future,
          ]).timeout(const Duration(milliseconds: 250));
          expect(runRequests, hasLength(1));
          expect(reportRequests, hasLength(1));
          expect(runRequests.single.queryParameters, {'active': 'true'});
        } finally {
          if (!releaseResponses.isCompleted) releaseResponses.complete();
        }
        await load;
      },
    );

    test(
      'loads active runs and completed reports without creating a run',
      () async {
        final requests = <Uri>[];
        final api = _api((request) async {
          requests.add(request.url);
          final body = switch (request.url.path) {
            '/api/report-generation-runs' => [
              {
                'id': 'run-decision',
                'origin': 'user_initiated',
                'state': 'awaiting_selection',
                'intent': '总结最近的跑步训练',
                'pending_decision': {
                  'type': 'plan_selection',
                  'recommended_option_id': 'option-1',
                },
                'plan_options': [
                  {
                    'id': 'option-1',
                    'recommended': true,
                    'title': '七月跑步复盘',
                    'summary': '分析里程、配速和恢复情况',
                  },
                ],
                'created_at': '2026-08-04T08:00:00Z',
                'updated_at': '2026-08-04T08:01:00Z',
              },
              {
                'id': 'run-generating',
                'origin': 'trigger',
                'state': 'generating',
                'active_stage': 'content_generation',
                'intent': '会前调研',
                'report_id': 'report-wip',
                'created_at': '2026-08-04T07:00:00Z',
                'updated_at': '2026-08-04T07:02:00Z',
              },
            ],
            '/api/reports' => [
              {
                'id': 'report-1',
                'title': '七月网球战报',
                'html': '<html>report</html>',
                'base_family': 'data_trend',
                'share_card': {'summary': '12 场 · 8 胜'},
                'created_at': '2026-08-03T08:00:00Z',
              },
            ],
            _ => throw StateError(
              'unexpected ${request.method} ${request.url}',
            ),
          };
          return _json(body);
        });
        addTearDown(api.close);

        final overview = await ApiReportRepository(api).loadOverview();

        expect(
          requests.map((uri) => uri.path),
          containsAll(['/api/report-generation-runs', '/api/reports']),
        );
        expect(requests, hasLength(2));
        expect(
          requests
              .singleWhere((uri) => uri.path == '/api/report-generation-runs')
              .queryParameters,
          {'active': 'true'},
        );
        expect(overview.activeRuns, hasLength(2));
        expect(overview.activeRuns.first.needsDecision, isTrue);
        expect(overview.activeRuns.first.title, '七月跑步复盘');
        expect(overview.activeRuns.first.intent, '总结最近的跑步训练');
        expect(overview.activeRuns.last.activeStage, 'content_generation');
        expect(overview.activeRuns.last.reportId, 'report-wip');
        expect(overview.activeRuns.last.createdAt, isNotNull);
        expect(overview.activeRuns.last.updatedAt, isNotNull);
        expect(overview.completedReports.single.title, '七月网球战报');
        expect(overview.completedReports.single.summary, '12 场 · 8 胜');
        expect(overview.completedReports.single.html, '<html>report</html>');
        expect(overview.completedReports.single.createdAt, isNotNull);
        expect(overview.failedSources, isEmpty);
        expect(requests.map((uri) => uri.path), isNot(contains('/api/assets')));
      },
    );

    test('retains active runs when completed reports fail', () async {
      final api = _api((request) async {
        if (request.url.path == '/api/report-generation-runs') {
          return _json([
            {'id': 'run-1', 'state': 'planning', 'intent': '整理汽车灵感'},
          ]);
        }
        return _json({'detail': 'unavailable'}, statusCode: 503);
      });
      addTearDown(api.close);

      final overview = await ApiReportRepository(api).loadOverview();

      expect(overview.activeRuns.single.id, 'run-1');
      expect(overview.completedReports, isEmpty);
      expect(overview.failedSources.single.source, 'reports');
    });

    test(
      'fails closed to the backend active run states without synthesis',
      () async {
        final api = _api((request) async {
          if (request.url.path == '/api/report-generation-runs') {
            return _json([
              for (final state in [
                'planning',
                'awaiting_selection',
                'generating',
                'failed',
              ])
                {'id': 'run-$state', 'state': state, 'intent': state},
              {
                'id': 'run-completed',
                'state': 'completed',
                'intent': '不应从运行列表生成报告',
                'report_id': 'report-not-returned',
              },
              for (final state in ['cancelled', 'expired', ' planning '])
                {'id': 'run-$state', 'state': state, 'intent': state},
            ]);
          }
          return _json([]);
        });
        addTearDown(api.close);

        final overview = await ApiReportRepository(api).loadOverview();

        expect(overview.activeRuns.map((run) => run.state), [
          'planning',
          'awaiting_selection',
          'generating',
          'failed',
        ]);
        expect(
          overview.activeRuns.map((run) => run.id),
          isNot(contains('run-completed')),
        );
        expect(overview.completedReports, isEmpty);
      },
    );

    test('freezes nested JSON fields in run summaries', () async {
      final api = _api((request) async {
        if (request.url.path == '/api/report-generation-runs') {
          return _json([
            {
              'id': 'run-frozen',
              'state': 'awaiting_selection',
              'pending_decision': {
                'details': {
                  'labels': ['priority'],
                },
              },
              'plan_options': [
                {
                  'title': '不可变方案',
                  'metadata': {
                    'labels': ['recommended'],
                  },
                },
              ],
            },
          ]);
        }
        return _json([]);
      });
      addTearDown(api.close);

      final run = (await ApiReportRepository(
        api,
      ).loadOverview()).activeRuns.single;
      final pendingDetails = run.pendingDecision['details'] as Map;
      final pendingLabels = pendingDetails['labels'] as List;
      final optionMetadata = run.planOptions.single['metadata'] as Map;
      final optionLabels = optionMetadata['labels'] as List;

      expect(() => run.pendingDecision['new'] = true, throwsUnsupportedError);
      expect(() => pendingDetails['new'] = true, throwsUnsupportedError);
      expect(() => pendingLabels.add('mutated'), throwsUnsupportedError);
      expect(() => run.planOptions.add(const {}), throwsUnsupportedError);
      expect(
        () => run.planOptions.single['new'] = true,
        throwsUnsupportedError,
      );
      expect(() => optionMetadata['new'] = true, throwsUnsupportedError);
      expect(() => optionLabels.add('mutated'), throwsUnsupportedError);
    });

    test(
      'rejects malformed scalar display fields instead of stringifying JSON',
      () async {
        final api = _api((request) async {
          if (request.url.path == '/api/report-generation-runs') {
            return _json([
              {
                'id': 'run-malformed-fields',
                'origin': {'unexpected': true},
                'state': 'planning',
                'intent': ['unexpected'],
                'active_stage': {'unexpected': true},
              },
            ]);
          }
          return _json([
            {
              'id': 'report-malformed-fields',
              'title': ['unexpected'],
              'html': {'unexpected': true},
            },
          ]);
        });
        addTearDown(api.close);

        final overview = await ApiReportRepository(api).loadOverview();

        expect(overview.activeRuns.single.origin, isEmpty);
        expect(overview.activeRuns.single.intent, isEmpty);
        expect(overview.activeRuns.single.activeStage, isNull);
        expect(overview.completedReports.single.title, '报告');
        expect(overview.completedReports.single.html, isEmpty);
      },
    );

    test('skips malformed rows from both top-level response arrays', () async {
      final api = _api((request) async {
        if (request.url.path == '/api/report-generation-runs') {
          return _json([
            'not-a-row',
            {
              'id': ['not-an-id'],
            },
            {'id': ''},
            {
              'id': 'valid-run',
              'state': 'failed',
              'intent': '有效报告任务',
              'failure': {'message': '生成失败'},
            },
          ]);
        }
        return _json([
          1,
          {
            'id': ['not-an-id'],
          },
          {'id': ''},
          {'id': 'valid-report', 'title': '有效报告', 'html': '<html>valid</html>'},
        ]);
      });
      addTearDown(api.close);

      final overview = await ApiReportRepository(api).loadOverview();

      expect(overview.activeRuns.map((run) => run.id), ['valid-run']);
      expect(overview.completedReports.map((report) => report.id), [
        'valid-report',
      ]);
      expect(overview.activeRuns.single.failureMessage, '生成失败');
      expect(overview.completedReports.single.html, '<html>valid</html>');
    });

    test('all offline sources produce a typed offline failure', () async {
      final api = _api(
        (request) async => throw http.ClientException('offline', request.url),
      );
      addTearDown(api.close);

      await expectLater(
        ApiReportRepository(api).loadOverview(),
        throwsA(
          isA<ReportLoadFailure>().having(
            (failure) => failure.isOffline,
            'isOffline',
            isTrue,
          ),
        ),
      );
    });

    test('all failed sources produce a non-offline load failure', () async {
      final api = _api(
        (request) async => _json({'detail': 'unavailable'}, statusCode: 503),
      );
      addTearDown(api.close);

      await expectLater(
        ApiReportRepository(api).loadOverview(),
        throwsA(
          isA<ReportLoadFailure>().having(
            (failure) => failure.isOffline,
            'isOffline',
            isFalse,
          ),
        ),
      );
    });
  });
}

ApiClient _api(Future<http.Response> Function(http.Request request) handler) =>
    ApiClient(
      client: MockClient(handler),
      baseUrl: 'https://reports.test',
      enableLogging: false,
    );

http.Response _json(Object body, {int statusCode = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
