import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/report/report_run_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('manual report creation posts an intent-only user run', () async {
    final requested = <String>[];
    final api = _api((request) async {
      requested.add('${request.method} ${request.url.path}');
      expect(jsonDecode(request.body), {
        'origin': 'user_initiated',
        'intent': '总结最近的跑步训练',
      });
      return _json({
        'id': 'run-manual',
        'origin': 'user_initiated',
        'state': 'planning',
        'intent': '总结最近的跑步训练',
      });
    });
    final controller = ReportRunController(api: api, autoPoll: false);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.startUserInitiated('  总结最近的跑步训练  ');

    expect(controller.runId, 'run-manual');
    expect(controller.state, 'planning');
    expect(requested, ['POST /api/report-generation-runs']);
  });

  test('active report run can be cancelled', () async {
    final requested = <String>[];
    final api = _api((request) async {
      requested.add('${request.method} ${request.url.path}');
      if (request.method == 'GET') {
        return _json({
          'id': 'run-1',
          'state': 'generating',
          'intent': '汽车灵感升华',
        });
      }
      expect(jsonDecode(request.body), isEmpty);
      return _json({'id': 'run-1', 'state': 'cancelled'});
    });
    final controller = ReportRunController(api: api, autoPoll: false);
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    await controller.loadRun('run-1');

    await controller.cancel();

    expect(controller.state, 'cancelled');
    expect(requested, [
      'GET /api/report-generation-runs/run-1',
      'POST /api/report-generation-runs/run-1/cancel',
    ]);
  });

  test('terminal report runs cannot be cancelled', () async {
    final requested = <String>[];
    final api = _api((request) async {
      requested.add('${request.method} ${request.url.path}');
      return _json({'id': 'run-completed', 'state': 'completed'});
    });
    final controller = ReportRunController(api: api, autoPoll: false);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.loadRun('run-completed');
    await controller.cancel();

    expect(controller.canCancel, isFalse);
    expect(controller.state, 'completed');
    expect(requested, ['GET /api/report-generation-runs/run-completed']);
  });

  test(
    'disposing during manual creation ignores a delayed run response',
    () async {
      final response = Completer<http.Response>();
      var requestCount = 0;
      final api = _api((request) {
        requestCount++;
        return response.future;
      });
      final controller = ReportRunController(
        api: api,
        pollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(api.close);

      final started = controller.startUserInitiated('总结最近的跑步训练');
      controller.dispose();
      response.complete(_json({'id': 'run-delayed', 'state': 'planning'}));
      await started;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.runId, isEmpty);
      expect(requestCount, 1);
    },
  );

  test(
    'disposing during cancellation ignores a delayed cancel response',
    () async {
      final cancelResponse = Completer<http.Response>();
      var requestCount = 0;
      final api = _api((request) {
        requestCount++;
        if (request.method == 'GET') {
          return Future.value(_json({'id': 'run-1', 'state': 'planning'}));
        }
        return cancelResponse.future;
      });
      final controller = ReportRunController(api: api, autoPoll: false);
      addTearDown(api.close);
      await controller.loadRun('run-1');

      final cancelled = controller.cancel();
      controller.dispose();
      cancelResponse.complete(_json({'id': 'run-1', 'state': 'cancelled'}));
      await cancelled;

      expect(controller.state, 'planning');
      expect(requestCount, 2);
    },
  );
}

ApiClient _api(Future<http.Response> Function(http.Request request) handler) =>
    ApiClient(
      client: MockClient(handler),
      baseUrl: 'https://reports.test',
      enableLogging: false,
    );

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
