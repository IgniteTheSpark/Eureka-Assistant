import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/library/library_models.dart';
import 'package:eureka/theme_v2/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiLibraryRepository', () {
    test(
      'loads one bounded overview and projects recent asset cards',
      () async {
        final calls = <String, int>{};
        final requestedUris = <Uri>[];
        final api = _api((request) async {
          requestedUris.add(request.url);
          calls.update(
            request.url.path,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          final body = switch (request.url.path) {
            '/api/assets' => {'assets': _assetRows(55)},
            '/api/skills' => {
              'skills': [
                _skill(
                  name: 'todo',
                  label: '待办',
                  mark: '☑',
                  primaryField: 'title',
                ),
                _skill(
                  name: 'notes',
                  label: '随记',
                  mark: '✎',
                  primaryField: 'content',
                ),
                _skill(
                  name: 'tennis',
                  label: '网球',
                  mark: '🎾',
                  primaryField: 'headline',
                ),
                _skill(
                  name: 'external_ref',
                  label: '外部资料',
                  mark: '↗',
                  primaryField: 'title',
                ),
                _skill(
                  name: 'qa',
                  label: '问答',
                  mark: '?',
                  primaryField: 'question',
                ),
              ],
            },
            '/api/events' => {
              'events': [
                {'id': 'event-1'},
              ],
            },
            '/api/contacts' => {
              'contacts': [
                {'id': 'contact-1'},
              ],
            },
            '/api/assets/counts' => {
              'counts': {'todo': 48, 'notes': 23, 'tennis': 3},
            },
            '/api/reports' => [
              {'id': 'report-1'},
              {'id': 'report-2'},
            ],
            _ => throw StateError('unexpected ${request.url}'),
          };
          return _json(body);
        });
        addTearDown(api.close);

        final overview = await ApiLibraryRepository(api).loadOverview();

        expect(calls, hasLength(6));
        expect(calls.values, everyElement(1));
        expect(calls['/api/skills'], 1);
        expect(calls['/api/reports'], 1);
        expect(
          requestedUris
              .singleWhere((uri) => uri.path == '/api/assets')
              .queryParameters,
          {'limit': '100'},
        );
        expect(
          overview.systemContainers.map((container) => container.type),
          LibraryContainerType.values.where(
            (type) => type != LibraryContainerType.custom,
          ),
        );
        expect(overview.customContainers.map((container) => container.id), [
          'tennis',
        ]);
        expect(overview.containerCount, 6);
        expect(overview.customContainerCount, 1);
        expect(overview.totalAssetCount, 74);
        expect(
          overview.systemContainers
              .singleWhere(
                (container) => container.type == LibraryContainerType.event,
              )
              .mark,
          '📅',
        );
        expect(
          overview.systemContainers
              .singleWhere(
                (container) => container.type == LibraryContainerType.event,
              )
              .label,
          '日程',
        );
        expect(
          overview.systemContainers
              .singleWhere(
                (container) => container.type == LibraryContainerType.contact,
              )
              .mark,
          '👤',
        );
        expect(
          overview.systemContainers
              .singleWhere(
                (container) => container.type == LibraryContainerType.report,
              )
              .totalCount,
          2,
        );
        expect(overview.recentAssets, hasLength(50));
        expect(overview.recentAssets.first.id, 'asset-54');
        expect(overview.recentAssets.first.primaryValue, '自定义主标题 54');
        expect(overview.recentAssets.first.mark, '🎾');
        expect(
          overview.recentAssets.map((asset) => asset.id),
          isNot(contains(anyOf('event-1', 'contact-1'))),
        );
      },
    );

    test('keeps five system containers when optional sources fail', () async {
      final api = _api((request) async {
        if (request.url.path == '/api/events' ||
            request.url.path == '/api/assets/counts') {
          return _json({'detail': 'temporarily unavailable'}, statusCode: 503);
        }
        final body = switch (request.url.path) {
          '/api/assets' => {'assets': _assetRows(2)},
          '/api/skills' => {
            'skills': [
              _skill(
                name: 'tennis',
                label: '网球',
                mark: '🎾',
                primaryField: 'headline',
              ),
            ],
          },
          '/api/contacts' => {'contacts': <Object>[]},
          '/api/reports' => <Object>[],
          _ => throw StateError('unexpected ${request.url}'),
        };
        return _json(body);
      });
      addTearDown(api.close);

      final overview = await ApiLibraryRepository(api).loadOverview();

      expect(overview.systemContainers, hasLength(5));
      expect(
        overview.systemContainers.map((container) => container.type),
        LibraryContainerType.values.where(
          (type) => type != LibraryContainerType.custom,
        ),
      );
      expect(overview.failedSources.map((failure) => failure.source), {
        'events',
        'counts',
      });
      expect(
        overview.systemContainers
            .singleWhere(
              (container) => container.type == LibraryContainerType.event,
            )
            .totalCount,
        0,
      );
      expect(overview.totalAssetCount, 2);
    });

    test(
      'pins expense and contact icons while preserving custom icons',
      () async {
        final api = _api((request) async {
          final body = switch (request.url.path) {
            '/api/assets' => {
              'assets': [
                {
                  'id': 'expense-1',
                  'user_skill_id': 'skill-expense',
                  'payload': {'amount': 38, 'description': '咖啡'},
                  'created_at': '2026-08-06T08:00:00Z',
                },
                {
                  'id': 'run-1',
                  'user_skill_id': 'skill-running_training',
                  'payload': {'headline': '五公里轻松跑'},
                  'created_at': '2026-08-06T07:00:00Z',
                },
              ],
            },
            '/api/skills' => {
              'skills': [
                _skill(
                  name: 'expense',
                  label: '消费',
                  mark: '🍔',
                  primaryField: 'amount',
                  isSystem: true,
                ),
                _skill(
                  name: 'contact',
                  label: '联系人',
                  mark: '🪪',
                  primaryField: 'name',
                  isSystem: true,
                ),
                _skill(
                  name: 'running_training',
                  label: '跑步训练',
                  mark: '🏃',
                  primaryField: 'headline',
                  isSystem: false,
                ),
              ],
            },
            '/api/events' => {'events': <Object>[]},
            '/api/contacts' => {'contacts': <Object>[]},
            '/api/assets/counts' => {
              'counts': {'expense': 1, 'running_training': 1},
            },
            '/api/reports' => <Object>[],
            _ => throw StateError('unexpected ${request.url}'),
          };
          return _json(body);
        });
        addTearDown(api.close);

        final overview = await ApiLibraryRepository(api).loadOverview();

        expect(
          overview.systemContainers
              .singleWhere((container) => container.id == 'contact')
              .mark,
          '👤',
        );
        expect(
          overview.systemContainers
              .singleWhere((container) => container.id == 'expense')
              .mark,
          '💳',
        );
        expect(
          overview.systemContainers
              .singleWhere((container) => container.id == 'expense')
              .isSystem,
          isTrue,
        );
        expect(
          overview.customContainers
              .singleWhere((container) => container.id == 'running_training')
              .mark,
          '🏃',
        );
        expect(
          overview.recentAssets
              .singleWhere((asset) => asset.skillName == 'expense')
              .mark,
          '💳',
        );
        expect(
          overview.recentAssets
              .singleWhere((asset) => asset.skillName == 'running_training')
              .mark,
          '🏃',
        );
      },
    );

    test(
      'adapts Theme V2 core-record lists without a false partial state',
      () async {
        final api = _api((request) async {
          switch (request.url.path) {
            case '/api/assets':
              return _json([
                for (var index = 0; index < 54; index++)
                  {
                    'id': 'core-asset-$index',
                    'user_skill_id': 'core-notes',
                    'payload': {'content': 'Theme V2 note $index'},
                    'effective_at': '2026-08-02T05:00:00Z',
                    'created_at': DateTime.utc(
                      2026,
                      8,
                      2,
                    ).add(Duration(minutes: index)).toIso8601String(),
                  },
              ]);
            case '/api/skills':
              return _json({'detail': 'Not Found'}, statusCode: 404);
            case '/api/user-skills':
              return _json([
                {
                  'id': 'core-notes',
                  'machine_name': 'notes',
                  'display_name': '随记',
                  'domain': 'knowledge',
                  'schema': {
                    'content': {'type': 'string'},
                  },
                },
              ]);
            case '/api/events':
              return _json([
                {'id': 'core-event'},
              ]);
            case '/api/contacts':
            case '/api/assets/counts':
              return _json({'detail': 'Not Found'}, statusCode: 404);
            case '/api/reports':
              return _json([]);
            default:
              throw StateError('unexpected ${request.url}');
          }
        });
        addTearDown(api.close);

        final overview = await ApiLibraryRepository(api).loadOverview();

        expect(overview.failedSources, isEmpty);
        expect(overview.totalAssetCount, 54);
        expect(overview.recentAssets, hasLength(50));
        expect(overview.recentAssets.first.skillName, 'notes');
        expect(overview.recentAssets.first.skillLabel, '随记');
        expect(
          overview.systemContainers
              .singleWhere(
                (container) => container.type == LibraryContainerType.notes,
              )
              .totalCount,
          54,
        );
        expect(
          overview.systemContainers
              .singleWhere(
                (container) => container.type == LibraryContainerType.event,
              )
              .totalCount,
          1,
        );
      },
    );

    test('preserves custom skill render icon in core-record mode', () async {
      final api = _api((request) async {
        final body = switch (request.url.path) {
          '/api/assets' => [
            {
              'id': 'run-1',
              'user_skill_id': 'skill-running',
              'payload': {'title': '五公里轻松跑'},
              'created_at': '2026-08-04T07:30:00Z',
            },
          ],
          '/api/user-skills' => [
            {
              'id': 'skill-running',
              'machine_name': 'running_training',
              'display_name': '跑步训练',
              'domain': 'health',
              'schema': {
                'title': {'type': 'string'},
              },
              'render_spec': {
                'icon': '🏃',
                'accent_color': 'green',
                'primary_field': 'title',
              },
            },
          ],
          '/api/events' => <Object>[],
          '/api/contacts' => {
            'contacts': [
              {'id': 'contact-alex-1', 'name': 'Alex'},
              {'id': 'contact-alex-2', 'name': 'Alex'},
            ],
          },
          '/api/reports' => <Object>[],
          _ => throw StateError('unexpected ${request.url}'),
        };
        return _json(body);
      });
      addTearDown(api.close);

      final overview = await ApiLibraryRepository(
        api,
        coreRecordsOnly: true,
      ).loadOverview();

      expect(
        overview.customContainers
            .singleWhere((container) => container.id == 'running_training')
            .mark,
        '🏃',
      );
      expect(overview.recentAssets.single.mark, '🏃');
      expect(
        overview.systemContainers
            .singleWhere((container) => container.id == 'contact')
            .totalCount,
        2,
      );
    });

    test('all offline sources produce a typed offline failure', () async {
      final api = _api(
        (request) async => throw http.ClientException('offline', request.url),
      );
      addTearDown(api.close);

      await expectLater(
        ApiLibraryRepository(api).loadOverview(),
        throwsA(
          isA<LibraryLoadFailure>().having(
            (failure) => failure.isOffline,
            'isOffline',
            isTrue,
          ),
        ),
      );
    });
  });
}

ApiClient _api(Future<http.Response> Function(http.Request request) handler) =>
    ApiClient(
      client: MockClient(handler),
      baseUrl: 'https://library.test',
      enableLogging: false,
    );

http.Response _json(Object body, {int statusCode = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _skill({
  required String name,
  required String label,
  required String mark,
  required String primaryField,
  bool? isSystem,
}) => {
  'id': 'skill-$name',
  'name': name,
  'display_name': label,
  'enabled': 1,
  'is_system': ?isSystem,
  'render_spec': {
    'icon': mark,
    'accent_color': 'blue',
    'primary_field': primaryField,
    'card_display': {
      'primary_field_id': primaryField,
      'secondary_field_ids': <String>[],
    },
  },
  'payload_schema': {
    primaryField: {'type': 'string', 'label': '主字段'},
  },
};

List<Map<String, dynamic>> _assetRows(int count) => [
  for (var index = 0; index < count; index++)
    {
      'id': 'asset-$index',
      'user_skill_name': 'tennis',
      'user_skill_id': 'skill-tennis',
      'payload': {'headline': '自定义主标题 $index'},
      'created_at': DateTime.utc(
        2026,
        7,
        1,
      ).add(Duration(minutes: index)).toIso8601String(),
    },
];
