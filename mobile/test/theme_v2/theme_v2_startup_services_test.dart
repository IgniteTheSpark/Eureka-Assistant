import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/startup_capabilities.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/inbox/reka_inbox_controller.dart';
import 'package:eureka/theme_v2/library/library_repository.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'theme_v2_test_app.dart';

void main() {
  test('Theme V2 keeps hardware services without legacy product services', () {
    const policy = StartupCapabilities.themeV2();

    expect(policy.hardwareCapture, isTrue);
    expect(policy.notifications, isTrue);
    expect(policy.pet, isFalse);
    expect(policy.nudges, isFalse);
    expect(policy.offers, isFalse);
    expect(policy.legacyTimeline, isFalse);
    expect(policy.legacyContacts, isFalse);
    expect(policy.legacySkills, isFalse);
  });

  test('Theme V2 repositories call only isolated core-record routes', () async {
    final calls = <String>[];
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        calls.add(request.url.path);
        return switch (request.url.path) {
          '/ready' => _json({'status': 'ready'}),
          '/api/user-skills' || '/api/assets' || '/api/events' => _json([]),
          _ => _json({'detail': 'unexpected ${request.url.path}'}, 500),
        };
      }),
    );
    addTearDown(api.close);

    await ApiThemeV2HomeRepository(api: api).load();
    await ApiLibraryRepository(api, coreRecordsOnly: true).loadOverview();
    await fetchTimeline(api, coreRecordsOnly: true);
    await fetchSkills(api, coreRecordsOnly: true);

    expect(calls, isNot(contains('/api/timeline')));
    expect(calls, isNot(contains('/api/skills')));
    expect(calls, isNot(contains('/api/contacts')));
    expect(calls, isNot(contains('/api/sessions')));
    expect(calls, isNot(contains('/api/assets/counts')));
    expect(
      calls,
      everyElement(
        isIn({'/ready', '/api/user-skills', '/api/assets', '/api/events'}),
      ),
    );
  });

  testWidgets('Theme V2 shell does not recover legacy nudges on mount', (
    tester,
  ) async {
    final repository = _CountingInboxRepository();
    final controller = RekaInboxController(
      repository: repository,
      observeNudgeStore: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ThemeV2TestApp(
        child: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          inboxController: controller,
          pages: const [
            ThemeV2PageScaffold(body: Text('today')),
            ThemeV2PageScaffold(body: Text('calendar')),
            ThemeV2PageScaffold(body: Text('library')),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(repository.loadCalls, 0);
  });
}

http.Response _json(Object body, [int statusCode = 200]) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json'},
);

class _CountingInboxRepository implements RekaInboxRepository {
  int loadCalls = 0;

  Future<List<Map<String, dynamic>>> _load() async {
    loadCalls++;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> loadOffers() => _load();

  @override
  Future<List<Map<String, dynamic>>> loadPending() => _load();

  @override
  Future<List<Map<String, dynamic>>> loadRecent() => _load();

  @override
  Future<void> outcome(String id, String status) async {}
}
