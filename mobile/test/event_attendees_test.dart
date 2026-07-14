import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pages/create_asset.dart';
import 'package:eureka/pages/event_attendees.dart';
import 'package:eureka/render/asset_detail_sheet.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  test('event id extraction accepts a nested map response', () {
    expect(
      eventIdFromCreateResponse(const {
        'ok': true,
        'event': {'event_id': 'event-nested'},
      }),
      'event-nested',
    );
  });

  test(
    'event attendee refresh distinguishes missing data from an empty list',
    () {
      expect(eventAttendeesFromResponse(const {'ok': true}), isNull);
      expect(
        eventAttendeesFromResponse(const {'ok': true, 'attendees': []}),
        isEmpty,
      );
    },
  );

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

  test(
    'attendee sync treats a missing DELETE target as already removed',
    () async {
      final requests = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response(
            jsonEncode({'ok': request.method != 'DELETE'}),
            request.method == 'DELETE' ? 404 : 200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await syncEventAttendees(
        api,
        eventId: 'event-1',
        original: [
          EventAttendeeDraft.fromJson(const {
            'id': 'a1',
            'contact_id': 'c1',
            'display_name': 'Removed',
            'is_resolved': true,
          }),
        ],
        current: [
          EventAttendeeDraft.fromContact(
            ContactChoice.fromJson(const {'id': 'c2', 'name': 'New'}),
          ),
        ],
      );

      expect(requests, [
        'DELETE /api/events/event-1/attendees/a1',
        'POST /api/events/event-1/attendees',
      ]);
    },
  );

  testWidgets(
    'event form renders enriched and legacy attendees without avatars',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: EventForm(
              existing: const {
                'title': 'Planning',
                'start_at': '2026-07-13T09:00:00+08:00',
                'end_at': '2026-07-13T10:00:00+08:00',
                'attendees': [
                  {
                    'id': 'a1',
                    'contact_id': 'c1',
                    'display_name': 'Alex Chen',
                    'contact_summary': 'Acme · PM',
                    'is_resolved': true,
                  },
                  {
                    'attendee_id': 'a2',
                    'name': 'Legacy Lee',
                    'contact_id': null,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('参会人'), findsOneWidget);
      expect(find.text('Alex Chen'), findsOneWidget);
      expect(find.text('Acme · PM'), findsOneWidget);
      expect(find.text('Legacy Lee'), findsOneWidget);
      expect(find.text('未关联联系人'), findsOneWidget);
      expect(find.text('关联'), findsOneWidget);
      expect(find.text('添加参会人'), findsOneWidget);
      expect(find.textContaining('Alex Chen +1'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
    },
  );

  testWidgets('event form removes one attendee without disturbing order', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: EventForm(
            existing: const {
              'title': 'Planning',
              'attendees': [
                {
                  'id': 'a1',
                  'contact_id': 'c1',
                  'display_name': 'First Person',
                  'is_resolved': true,
                },
                {
                  'id': 'a2',
                  'contact_id': 'c2',
                  'display_name': 'Second Person',
                  'is_resolved': true,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byTooltip('移除参会人').first);
    await tester.pump();
    await tester.tap(find.byTooltip('移除参会人').first);
    await tester.pump();

    expect(find.text('First Person'), findsNothing);
    expect(find.text('Second Person'), findsOneWidget);
  });

  testWidgets('event form opens the multi-select attendee picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: const EventForm(existing: {'title': 'Planning'}),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('添加参会人'));
    await tester.pump();

    expect(find.text('选择参会人'), findsOneWidget);
    expect(find.text('可选择多个联系人'), findsOneWidget);
  });

  testWidgets(
    'event form adds selected contacts in order and filters duplicates',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'contacts': [
                {'id': 'c1', 'name': 'Already Bound'},
                {'id': 'c2', 'name': 'New One', 'company': 'Acme'},
                {'id': 'c3', 'name': 'New Two', 'title': 'Designer'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: EventForm(
              api: api,
              existing: const {
                'title': 'Planning',
                'attendees': [
                  {
                    'id': 'a1',
                    'contact_id': 'c1',
                    'display_name': 'Already Bound',
                    'is_resolved': true,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('添加参会人'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.byKey(const ValueKey('c1'))),
        findsNothing,
      );
      await tester.tap(find.text('New One'));
      await tester.pump();
      await tester.tap(find.text('New Two'));
      await tester.pump();
      await tester.tap(find.text('保存(2)'));
      await tester.pumpAndSettle();

      expect(find.text('Already Bound'), findsOneWidget);
      expect(find.text('New One'), findsOneWidget);
      expect(find.text('New Two'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('New One')).dy,
        lessThan(tester.getTopLeft(find.text('New Two')).dy),
      );
    },
  );

  testWidgets('event form binds an unresolved persisted attendee once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'contacts': [
              {'id': 'c1', 'name': 'Already Bound'},
              {
                'id': 'c2',
                'name': 'Alex Bound',
                'company': 'Acme',
                'title': 'CTO',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: EventForm(
            api: api,
            existing: const {
              'title': 'Planning',
              'attendees': [
                {
                  'id': 'a1',
                  'name_raw': 'Alex Raw',
                  'display_name': 'Alex Raw',
                  'is_resolved': false,
                },
                {
                  'id': 'a2',
                  'contact_id': 'c1',
                  'display_name': 'Already Bound',
                  'is_resolved': true,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('关联'));
    await tester.pumpAndSettle();
    expect(find.text('选择一张名片完成绑定'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.byKey(const ValueKey('c1'))),
      findsNothing,
    );
    await tester.tap(find.text('Alex Bound'));
    await tester.pump();
    await tester.tap(find.text('保存(1)'));
    await tester.pumpAndSettle();

    expect(find.text('Alex Bound'), findsOneWidget);
    expect(find.text('Acme · CTO'), findsOneWidget);
    expect(find.text('未关联联系人'), findsNothing);
    expect(find.text('关联'), findsNothing);
  });

  testWidgets('event form preloads an unresolved attendee name when linking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final queries = <String?>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        queries.add(request.url.queryParameters['q']);
        return http.Response(
          jsonEncode({'contacts': const []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: EventForm(
            api: api,
            existing: const {
              'title': 'Planning',
              'attendees': [
                {
                  'id': 'a1',
                  'name_raw': 'Alex Raw',
                  'display_name': 'Alex Raw',
                  'is_resolved': false,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('关联'));
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(find.byType(TextField).last);
    expect(search.controller?.text, 'Alex Raw');
    expect(queries, ['Alex Raw']);
  });

  testWidgets('event detail lists a bare-name attendee as unlinked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const event = <String, dynamic>{
      'event_id': 'event-1',
      'title': 'Roadmap review',
      'start_at': '2026-07-14T17:00:00+08:00',
      'end_at': '2026-07-14T18:00:00+08:00',
      'location': '3楼会议室',
      'attendees': [
        {
          'id': 'a1',
          'name_raw': 'Kevin',
          'display_name': 'Kevin',
          'is_resolved': false,
        },
      ],
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAssetDetail(
              context,
              data: buildCard(
                payload: event,
                spec: synthesizeSpec('event'),
                displayName: 'event',
              ),
              payload: event,
              cardType: 'event',
              assetId: 'event-1',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Kevin'), findsOneWidget);
    expect(find.text('未关联联系人'), findsOneWidget);
    expect(find.text('关联'), findsOneWidget);
  });

  testWidgets('event detail links a bare-name attendee in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var linked = false;
    final operations = <String>[];
    Map<String, dynamic> event() => {
      'event_id': 'event-1',
      'title': 'Roadmap review',
      'start_at': '2026-07-14T17:00:00+08:00',
      'end_at': '2026-07-14T18:00:00+08:00',
      'location': '3楼会议室',
      'attendees': [
        linked
            ? {
                'id': 'a1',
                'contact_id': 'c-google',
                'name_raw': 'Kevin',
                'display_name': 'Kevin',
                'contact_summary': 'Google · 工程师',
                'is_resolved': true,
              }
            : {
                'id': 'a1',
                'name_raw': 'Kevin',
                'display_name': 'Kevin',
                'is_resolved': false,
              },
      ],
    };
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/events/event-1') {
          return http.Response(
            jsonEncode({'event': event()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/api/contacts') {
          operations.add('GET contacts q=${request.url.queryParameters['q']}');
          return http.Response(
            jsonEncode({
              'contacts': [
                {
                  'id': 'c-google',
                  'name': 'Kevin',
                  'company': 'Google',
                  'title': '工程师',
                },
                {
                  'id': 'c-abccc',
                  'name': 'Kevin',
                  'company': 'abccc',
                  'title': '产品经理',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path == '/api/events/event-1/attendees/a1') {
          operations.add('PATCH ${request.body}');
          linked = true;
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    final initialEvent = event();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAssetDetail(
              context,
              data: buildCard(
                payload: initialEvent,
                spec: synthesizeSpec('event'),
                displayName: 'event',
              ),
              payload: initialEvent,
              cardType: 'event',
              assetId: 'event-1',
              api: api,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关联'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Kevin',
    );
    expect(find.text('Google · 工程师'), findsOneWidget);
    expect(find.text('abccc · 产品经理'), findsOneWidget);
    await tester.tap(find.text('Google · 工程师'));
    await tester.pump();
    await tester.tap(find.text('保存(1)'));
    await tester.pumpAndSettle();

    expect(operations, [
      'GET contacts q=Kevin',
      'PATCH {"contact_id":"c-google"}',
    ]);
    expect(find.text('未关联联系人'), findsNothing);
    expect(find.text('Google · 工程师'), findsOneWidget);
  });

  testWidgets(
    'create saves the event before attendee posts using response id',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/contacts') {
            return http.Response(
              jsonEncode({
                'contacts': [
                  {'id': 'c1', 'name': 'First'},
                  {'id': 'c2', 'name': 'Second'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          operations.add(
            '${request.method} ${request.url.path}'
            '${request.body.isEmpty ? '' : ' ${request.body}'}',
          );
          if (request.method == 'POST' && request.url.path == '/api/events') {
            return http.Response(
              jsonEncode({'ok': true, 'event_id': 'event-new'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: EventForm(
              api: api,
              existing: const {
                'title': 'Planning',
                'start_at': '2026-07-13T09:00:00+08:00',
                'end_at': '2026-07-13T10:00:00+08:00',
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('添加参会人'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First'));
      await tester.pump();
      await tester.tap(find.text('Second'));
      await tester.pump();
      await tester.tap(find.text('保存(2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(operations, [
        startsWith('POST /api/events {'),
        'POST /api/events/event-new/attendees '
            '{"contact_id":"c1","role":"attendee"}',
        'POST /api/events/event-new/attendees '
            '{"contact_id":"c2","role":"attendee"}',
      ]);
    },
  );

  testWidgets(
    'attendee sync failure keeps edit draft open with a specific error',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'contacts': [
                  {'id': 'c2', 'name': 'Alex Bound', 'company': 'Acme'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          operations.add('${request.method} ${request.url.path}');
          if (request.method == 'PATCH') {
            return http.Response(
              jsonEncode({'detail': 'sync failed'}),
              500,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: EventForm(
              api: api,
              eventId: 'event-edit',
              existing: const {
                'title': 'Planning',
                'start_at': '2026-07-13T09:00:00+08:00',
                'end_at': '2026-07-13T10:00:00+08:00',
                'attendees': [
                  {
                    'id': 'a1',
                    'name_raw': 'Alex Raw',
                    'display_name': 'Alex Raw',
                    'is_resolved': false,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('关联'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex Bound'));
      await tester.pump();
      await tester.tap(find.text('保存(1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(operations, [
        'PUT /api/events/event-edit',
        'PATCH /api/events/event-edit/attendees/a1',
      ]);
      await tester.scrollUntilVisible(
        find.textContaining('保存参会人失败'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('保存参会人失败'), findsOneWidget);
      expect(find.text('EVENT'), findsOneWidget);
      expect(find.text('Alex Bound'), findsOneWidget);
    },
  );

  testWidgets(
    'partial attendee posts refresh before retrying only the remainder',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = <String>[];
      var secondAttendeeAttempts = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          final requestBody = request.body.isEmpty
              ? const <String, dynamic>{}
              : (jsonDecode(request.body) as Map).cast<String, dynamic>();
          final contactId = requestBody['contact_id'];
          operations.add(
            '${request.method} ${request.url.path}'
            '${contactId == null ? '' : ' $contactId'}',
          );
          if (request.method == 'POST' && request.url.path == '/api/events') {
            return http.Response(
              jsonEncode({'event_id': 'event-created'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/events/event-created') {
            return http.Response(
              jsonEncode({
                'event_id': 'event-created',
                'attendees': [
                  {
                    'id': 'a1',
                    'contact_id': 'c1',
                    'display_name': 'First',
                    'is_resolved': true,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/attendees') && contactId == 'c2') {
            secondAttendeeAttempts++;
            return http.Response(
              jsonEncode({'ok': secondAttendeeAttempts > 1}),
              secondAttendeeAttempts == 1 ? 500 : 200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: EventForm(
              api: api,
              existing: const {
                'title': 'Planning',
                'start_at': '2026-07-13T09:00:00+08:00',
                'end_at': '2026-07-13T10:00:00+08:00',
                'attendees': [
                  {
                    'contact_id': 'c1',
                    'display_name': 'First',
                    'is_resolved': true,
                  },
                  {
                    'contact_id': 'c2',
                    'display_name': 'Second',
                    'is_resolved': true,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(operations, [
        'POST /api/events',
        'POST /api/events/event-created/attendees c1',
        'POST /api/events/event-created/attendees c2',
        'GET /api/events/event-created',
        'PUT /api/events/event-created',
        'POST /api/events/event-created/attendees c2',
      ]);
    },
  );

  testWidgets('failed attendee refresh blocks unsafe retry until reopen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final operations = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        operations.add('${request.method} ${request.url.path}');
        if (request.method == 'POST' || request.method == 'GET') {
          return http.Response(
            jsonEncode({'detail': 'offline'}),
            500,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: EventForm(
            api: api,
            eventId: 'event-edit',
            existing: const {
              'title': 'Planning',
              'start_at': '2026-07-13T09:00:00+08:00',
              'end_at': '2026-07-13T10:00:00+08:00',
              'attendees': [
                {
                  'contact_id': 'c1',
                  'display_name': 'Unsafe Retry',
                  'is_resolved': true,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(operations, [
      'PUT /api/events/event-edit',
      'POST /api/events/event-edit/attendees',
      'GET /api/events/event-edit',
    ]);
    final saveButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '保存'),
    );
    expect(saveButton.onPressed, isNull);
    await tester.scrollUntilVisible(
      find.textContaining('状态刷新失败，请重新打开事件后再试'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('状态刷新失败，请重新打开事件后再试'), findsOneWidget);
  });

  testWidgets(
    'successful attendee delete is not repeated after later failure',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = <String>[];
      var postAttempts = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          final requestBody = request.body.isEmpty
              ? const <String, dynamic>{}
              : (jsonDecode(request.body) as Map).cast<String, dynamic>();
          final contactId = requestBody['contact_id'];
          operations.add(
            '${request.method} ${request.url.path}'
            '${contactId == null ? '' : ' $contactId'}',
          );
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({'event_id': 'event-edit', 'attendees': const []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST') {
            postAttempts++;
            return http.Response(
              jsonEncode({'ok': postAttempts > 1}),
              postAttempts == 1 ? 500 : 200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: EventForm(
              api: api,
              eventId: 'event-edit',
              existing: const {
                'title': 'Planning',
                'start_at': '2026-07-13T09:00:00+08:00',
                'end_at': '2026-07-13T10:00:00+08:00',
                'attendees': [
                  {
                    'id': 'a1',
                    'contact_id': 'c1',
                    'display_name': 'Remove Once',
                    'is_resolved': true,
                  },
                  {
                    'contact_id': 'c2',
                    'display_name': 'Fail Later',
                    'is_resolved': true,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('移除参会人').first);
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(operations, [
        'PUT /api/events/event-edit',
        'DELETE /api/events/event-edit/attendees/a1',
        'POST /api/events/event-edit/attendees c2',
        'GET /api/events/event-edit',
        'PUT /api/events/event-edit',
        'POST /api/events/event-edit/attendees c2',
      ]);
    },
  );

  testWidgets(
    'create without a response event id never sends an attendee path',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          operations.add('${request.method} ${request.url.path}');
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: EventForm(
              api: api,
              existing: const {
                'title': 'Planning',
                'start_at': '2026-07-13T09:00:00+08:00',
                'end_at': '2026-07-13T10:00:00+08:00',
                'attendees': [
                  {
                    'contact_id': 'c1',
                    'display_name': 'No Wrong Path',
                    'is_resolved': true,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(operations, ['POST /api/events']);
      await tester.scrollUntilVisible(
        find.textContaining('创建事件响应缺少 event_id'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('创建事件响应缺少 event_id'), findsOneWidget);
    },
  );

  testWidgets('failed event save prevents attendee deletion', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final operations = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        operations.add('${request.method} ${request.url.path}');
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode({'detail': 'event save failed'}),
            500,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: EventForm(
            api: api,
            eventId: 'event-edit',
            existing: const {
              'title': 'Planning',
              'start_at': '2026-07-13T09:00:00+08:00',
              'end_at': '2026-07-13T10:00:00+08:00',
              'attendees': [
                {
                  'id': 'a1',
                  'contact_id': 'c1',
                  'display_name': 'Remove Me',
                  'is_resolved': true,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('移除参会人'));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(operations, ['PUT /api/events/event-edit']);
  });

  testWidgets('remove then re-add of one contact is an unchanged attendee', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final operations = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/api/contacts') {
          return http.Response(
            jsonEncode({
              'contacts': [
                {'id': 'c1', 'name': 'Re-added'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        operations.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: EventForm(
            api: api,
            eventId: 'event-edit',
            existing: const {
              'title': 'Planning',
              'start_at': '2026-07-13T09:00:00+08:00',
              'end_at': '2026-07-13T10:00:00+08:00',
              'attendees': [
                {
                  'id': 'a1',
                  'contact_id': 'c1',
                  'display_name': 'Re-added',
                  'is_resolved': true,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('移除参会人'));
    await tester.pump();
    await tester.tap(find.text('添加参会人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-added'));
    await tester.pump();
    await tester.tap(find.text('保存(1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(operations, ['PUT /api/events/event-edit']);
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
                  onCreateContact: (_, _) async => null,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('选择参会人'), findsOneWidget);
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
      String? createdInitialName;
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
                  onCreateContact: (_, initialName) async {
                    createdInitialName = initialName;
                    return {
                      'contact_id': 'c3',
                      'contact': {
                        'id': 'c3',
                        'name': 'Alex Chen',
                        'company': 'Created Co',
                      },
                    };
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
      expect(find.text('选择参会人'), findsOneWidget);
      expect(find.text('选择一张名片完成绑定'), findsOneWidget);
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
      expect(createdInitialName, 'Alex');
      expect(find.text('Alex Chen'), findsOneWidget);
      expect(find.text('保存(1)'), findsOneWidget);
      await tester.tap(find.text('保存(1)'));
      await tester.pumpAndSettle();

      expect(result?.single.id, 'c3');
    },
  );

  testWidgets('selector footer shows selected names without avatars', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'contacts': const []}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventAttendeeSelector(
              context,
              api: api,
              initialSelection: const [
                ContactChoice(id: 'c1', name: 'Footer Alex'),
                ContactChoice(id: 'c2', name: 'Footer Bob'),
              ],
              onCreateContact: (_, _) async => null,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('已选'), findsOneWidget);
    expect(find.text('• Footer Alex'), findsOneWidget);
    expect(find.text('• Footer Bob'), findsOneWidget);
    expect(find.text('保存(2)'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets(
    'selector rejects an old response as soon as the search text changes',
    (tester) async {
      final oldResponse = Completer<http.Response>();
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          final query = request.url.queryParameters['q'];
          if (query == 'Old') return oldResponse.future;
          final contacts = query == 'New'
              ? [
                  {'id': 'new', 'name': 'New Result'},
                ]
              : const <Map<String, String>>[];
          return http.Response(
            jsonEncode({'contacts': contacts}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEurekaTheme(EurekaColors.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventAttendeeSelector(
                context,
                api: api,
                onCreateContact: (_, _) async => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Old');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'New');
      await tester.pump();

      oldResponse.complete(
        http.Response(
          jsonEncode({
            'contacts': [
              {'id': 'old', 'name': 'Old Result'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tester.pump();

      expect(find.text('Old Result'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('New Result'), findsOneWidget);
    },
  );

  testWidgets('selector contains create errors and restores the retry button', (
    tester,
  ) async {
    var attempts = 0;
    final api = ApiClient(
      baseUrl: 'http://localhost',
      enableLogging: false,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'contacts': const []}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.dark),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventAttendeeSelector(
              context,
              api: api,
              onCreateContact: (_, _) async {
                attempts++;
                throw StateError('create failed');
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增联系人'));
    await tester.pumpAndSettle();

    expect(find.text('新增联系人失败，请重试'), findsOneWidget);
    final retry = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '新增联系人'),
    );
    expect(retry.onPressed, isNotNull);
    await tester.tap(find.text('新增联系人'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
