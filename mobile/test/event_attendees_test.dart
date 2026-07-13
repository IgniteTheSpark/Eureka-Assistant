import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pages/create_asset.dart';
import 'package:eureka/pages/event_attendees.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('attendee models', () {
    test('parses unresolved attendees without inventing a contact', () {
      final attendee = EventAttendeeDraft.fromJson(const {
        'id': 'a1',
        'contact_id': null,
        'name_raw': 'Alex',
        'display_name': 'Alex',
        'is_resolved': false,
      });

      expect(attendee.id, 'a1');
      expect(attendee.contactId, isNull);
      expect(attendee.displayName, 'Alex');
      expect(attendee.isResolved, isFalse);
    });

    test('prefers enriched names and builds compact contact summaries', () {
      expect(
        contactSummary(const {'company': 'Acme', 'title': 'PM'}),
        'Acme · PM',
      );
      expect(
        eventAttendeeSummaryName(const {
          'display_name': 'Alex',
          'name_raw': 'Old',
        }),
        'Alex',
      );
      expect(
        eventAttendeeSummaryName(const {'name_raw': 'Old', 'name': 'Legacy'}),
        'Old',
      );
    });

    test('keeps same-name contacts distinct by id', () {
      final first = ContactChoice.fromJson(const {'id': 'c1', 'name': 'Alex'});
      final second = ContactChoice.fromJson(const {'id': 'c2', 'name': 'Alex'});

      expect(first, isNot(second));
      expect({first, second}, hasLength(2));
    });
  });

  test('contact creation receipt preserves card keys and created contact', () {
    final contact = {'id': 'c1', 'name': 'Alex', 'company': 'Acme'};

    expect(
      contactCreationReceipt({
        'ok': true,
        'contact_id': 'c1',
        'contact': contact,
      }, fallbackName: 'Alex'),
      {
        'user_skill_name': 'contact',
        'display_name': '联系人',
        'icon': '👤',
        'payload': {'name': 'Alex'},
        'contact_id': 'c1',
        'contact': contact,
      },
    );
  });

  test('syncs adds, removals and bindings while ignoring unchanged rows', () async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        requests.add(
          '${request.method} ${request.url.path} ${request.body.isEmpty ? '{}' : request.body}',
        );
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final unresolved = EventAttendeeDraft.fromJson(const {
      'id': 'a1',
      'contact_id': null,
      'name_raw': 'Alex',
      'display_name': 'Alex',
      'is_resolved': false,
    });
    final removed = EventAttendeeDraft.fromJson(const {
      'id': 'a2',
      'contact_id': 'c-old',
      'display_name': 'Removed',
      'is_resolved': true,
    });
    final unchanged = EventAttendeeDraft.fromJson(const {
      'id': 'a3',
      'contact_id': 'c-keep',
      'display_name': 'Kept',
      'is_resolved': true,
    });

    await syncEventAttendees(
      api,
      eventId: 'event-1',
      original: [unresolved, removed, unchanged],
      current: [
        unresolved.copyWith(
          contact: ContactChoice.fromJson(const {
            'id': 'c-alex',
            'name': 'Alex',
          }),
        ),
        unchanged,
        EventAttendeeDraft.fromContact(
          ContactChoice.fromJson(const {'id': 'c-new-1', 'name': 'New One'}),
        ),
        EventAttendeeDraft.fromContact(
          ContactChoice.fromJson(const {'id': 'c-new-2', 'name': 'New Two'}),
        ),
      ],
    );

    expect(requests, [
      'DELETE /api/events/event-1/attendees/a2 {}',
      'PATCH /api/events/event-1/attendees/a1 {"contact_id":"c-alex"}',
      'POST /api/events/event-1/attendees {"contact_id":"c-new-1","role":"attendee"}',
      'POST /api/events/event-1/attendees {"contact_id":"c-new-2","role":"attendee"}',
    ]);
  });

  testWidgets(
    'selector loads recent contacts and keeps duplicate names distinct',
    (tester) async {
      final queries = <Map<String, String>>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          queries.add(request.url.queryParameters);
          return http.Response(
            jsonEncode({
              'contacts': [
                {
                  'id': 'c1',
                  'name': 'Alex',
                  'company': 'Acme',
                  'title': 'PM',
                  'phone': '10086',
                },
                {
                  'id': 'c2',
                  'name': 'Alex',
                  'company': 'Beta',
                  'title': 'CTO',
                  'phone': '10010',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      List<ContactChoice>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showEventAttendeeSelector(
                  context,
                  api: api,
                  onCreateContact: (_) async => null,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(queries, [
        {'q': '', 'limit': '20'},
      ]);
      expect(find.text('Alex'), findsNWidgets(2));
      expect(find.text('Acme · PM'), findsOneWidget);
      expect(find.text('10086'), findsOneWidget);
      expect(find.text('保存(0)'), findsOneWidget);

      await tester.tap(find.text('Alex').first);
      await tester.pump();
      await tester.tap(find.text('Alex').last);
      await tester.pump();
      expect(find.text('保存(2)'), findsOneWidget);
      await tester.tap(find.text('保存(2)'));
      await tester.pumpAndSettle();

      expect(result?.map((choice) => choice.id), ['c1', 'c2']);
    },
  );

  testWidgets(
    'selector debounces search and auto-selects a newly created contact',
    (tester) async {
      final queries = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          queries.add(request.url.queryParameters['q'] ?? 'missing');
          return http.Response(
            jsonEncode({'contacts': const []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      List<ContactChoice>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEurekaTheme(EurekaColors.dark),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showEventAttendeeSelector(
                  context,
                  api: api,
                  singleSelect: true,
                  onCreateContact: (_) async => {
                    'contact_id': 'c3',
                    'contact': {
                      'id': 'c3',
                      'name': 'Alex Chen',
                      'company': 'Created Co',
                    },
                  },
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(queries, ['']);

      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.pump(const Duration(milliseconds: 299));
      expect(queries, ['']);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(queries, ['', 'Alex']);
      expect(find.text('新增联系人'), findsOneWidget);

      await tester.tap(find.text('新增联系人'));
      await tester.pumpAndSettle();
      expect(find.text('Alex Chen'), findsOneWidget);
      expect(find.text('保存(1)'), findsOneWidget);
      await tester.tap(find.text('保存(1)'));
      await tester.pumpAndSettle();

      expect(result?.single.id, 'c3');
    },
  );
}
