import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pet/reka_nudges.dart';
import 'package:eureka/theme_v2/inbox/reka_inbox_controller.dart';
import 'package:eureka/theme_v2/inbox/reka_inbox_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RekaInboxItem', () {
    test('parses the shared nudge and offer wire shape strictly', () {
      final item = RekaInboxItem.fromJson(const {
        'id': 'n-1',
        'type': 'nudge',
        'kind': 'overdue',
        'text': '跟进报价',
        'body': '已经逾期一天',
        'ref': 'todo:a-1',
        'cta': 'view',
        'status': 'delivered',
        'created_at': '2026-07-28T02:00:00Z',
      }, source: RekaInboxSource.pending);

      expect(item.id, 'n-1');
      expect(item.title, '跟进报价');
      expect(item.createdAt, DateTime.parse('2026-07-28T02:00:00Z').toLocal());
      expect(item.isUnread, isTrue);
      expect(item.sources, {RekaInboxSource.pending});
    });

    test('rejects rows without stable identity or readable text', () {
      expect(
        () => RekaInboxItem.fromJson(const {
          'text': 'missing id',
        }, source: RekaInboxSource.recent),
        throwsFormatException,
      );
      expect(
        () => RekaInboxItem.fromJson(const {
          'id': 'n-1',
        }, source: RekaInboxSource.recent),
        throwsFormatException,
      );
    });
  });

  group('RekaInboxController', () {
    test(
      'merges pending recent and offer rows by id and derives unread',
      () async {
        final repository = _FakeRepository(
          pending: [
            _row('shared', status: 'delivered'),
            _row('pending', status: 'pending', minute: 3),
          ],
          recent: [
            _row('shared', status: 'seen'),
            _row('acted', status: 'acted', minute: 2),
          ],
          offers: [
            _row('offer', status: 'pending', minute: 1),
            _row('shared', status: 'pending'),
          ],
        );
        final controller = RekaInboxController(repository: repository);

        await controller.load();

        expect(controller.status, RekaInboxStatus.ready);
        expect(controller.items.map((item) => item.id).toSet(), {
          'shared',
          'pending',
          'acted',
          'offer',
        });
        final shared = controller.items.singleWhere(
          (item) => item.id == 'shared',
        );
        expect(shared.status, 'seen');
        expect(shared.sources, {
          RekaInboxSource.pending,
          RekaInboxSource.recent,
          RekaInboxSource.offer,
        });
        expect(controller.unreadCount, 2);
      },
    );

    test('supports badge-only load without computing pull offers', () async {
      final repository = _FakeRepository(
        pending: [_row('pending', status: 'delivered')],
        recent: const [],
        offers: [_row('offer', status: 'pending')],
      );
      final controller = RekaInboxController(repository: repository);

      await controller.load(includeOffers: false);

      expect(repository.offerLoads, 0);
      expect(controller.items.map((item) => item.id), ['pending']);
      expect(controller.unreadCount, 1);
    });

    test(
      'keeps successful sources visible and identifies partial load',
      () async {
        final repository = _FakeRepository(
          pending: [_row('pending')],
          recent: const [],
          offers: const [],
        )..recentError = StateError('recent unavailable');
        final controller = RekaInboxController(repository: repository);

        await controller.load();

        expect(controller.status, RekaInboxStatus.partial);
        expect(controller.items.map((item) => item.id), ['pending']);
        expect(controller.errorMessage, contains('部分'));
      },
    );

    test(
      'total load failure exposes retry and later replaces the error',
      () async {
        final repository = _SequenceRepository();
        final controller = RekaInboxController(repository: repository);

        await controller.load();
        expect(controller.status, RekaInboxStatus.error);
        expect(controller.items, isEmpty);

        repository.fail = false;
        await controller.retry();
        expect(controller.status, RekaInboxStatus.ready);
        expect(controller.items.single.id, 'ready');
      },
    );

    test('empty is distinct from loading and error', () async {
      final controller = RekaInboxController(
        repository: _FakeRepository(
          pending: const [],
          recent: const [],
          offers: const [],
        ),
      );

      await controller.load();

      expect(controller.status, RekaInboxStatus.empty);
      expect(controller.errorMessage, isNull);
    });

    test(
      'outcome is optimistic and rolls back the current failed revision',
      () async {
        final repository = _FakeRepository(
          pending: [_row('n-1', status: 'delivered')],
          recent: const [],
          offers: const [],
        )..outcomeError = StateError('offline');
        final controller = RekaInboxController(repository: repository);
        await controller.load();

        final future = controller.markSeen('n-1');
        expect(controller.unreadCount, 0);
        expect(controller.itemById('n-1')?.status, 'seen');

        expect(await future, isFalse);
        expect(controller.itemById('n-1')?.status, 'delivered');
        expect(controller.unreadCount, 1);
        expect(controller.mutationError, contains('offline'));
      },
    );

    test(
      'acted and dismissed stay in history but no longer count unread',
      () async {
        final repository = _FakeRepository(
          pending: [
            _row('act', status: 'pending'),
            _row('dismiss', status: 'delivered', minute: 1),
          ],
          recent: const [],
          offers: const [],
        );
        final controller = RekaInboxController(repository: repository);
        await controller.load();

        expect(await controller.markActed('act'), isTrue);
        expect(await controller.markDismissed('dismiss'), isTrue);

        expect(controller.items, hasLength(2));
        expect(controller.itemById('act')?.status, 'acted');
        expect(controller.itemById('dismiss')?.status, 'dismissed');
        expect(controller.unreadCount, 0);
        expect(repository.outcomes, [
          ('act', 'acted'),
          ('dismiss', 'dismissed'),
        ]);
      },
    );

    test('mark all seen only mutates unread rows', () async {
      final repository = _FakeRepository(
        pending: [
          _row('one', status: 'pending'),
          _row('two', status: 'delivered', minute: 1),
        ],
        recent: [_row('done', status: 'acted', minute: 2)],
        offers: const [],
      );
      final controller = RekaInboxController(repository: repository);
      await controller.load();

      final success = await controller.markAllSeen();

      expect(success, isTrue);
      expect(controller.unreadCount, 0);
      expect(
        repository.outcomes,
        containsAll([('one', 'seen'), ('two', 'seen')]),
      );
      expect(
        repository.outcomes.where((outcome) => outcome.$1 == 'done'),
        isEmpty,
      );
    });

    test(
      'concurrent outcomes roll back per item without stomping success',
      () async {
        final repository = _ControlledOutcomeRepository(
          pending: [
            _row('one', status: 'pending'),
            _row('two', status: 'pending', minute: 1),
          ],
        );
        final controller = RekaInboxController(repository: repository);
        await controller.load();

        final first = controller.markSeen('one');
        final second = controller.markActed('two');
        await Future<void>.delayed(Duration.zero);
        expect(repository.pendingOutcomes, hasLength(1));

        repository.pendingOutcomes[0].completeError(StateError('first failed'));
        expect(await first, isFalse);
        await Future<void>.delayed(Duration.zero);
        repository.pendingOutcomes[1].complete();
        expect(await second, isTrue);

        expect(controller.itemById('one')?.status, 'pending');
        expect(controller.itemById('two')?.status, 'acted');
      },
    );

    test('dispose invalidates pending loads and outcomes', () async {
      final pending = Completer<List<Map<String, dynamic>>>();
      final repository = _PendingRepository(pending);
      final controller = RekaInboxController(repository: repository);

      final load = controller.load();
      controller.dispose();
      pending.complete([_row('late')]);

      await expectLater(load, completes);
    });

    test('shared Home outcome immediately updates Inbox badge state', () async {
      final store = RekaNudges.instance;
      store.reset();
      addTearDown(store.reset);
      store.pushArrival(
        const RekaNudge(id: 'shared', text: '共享提醒', status: 'delivered'),
      );
      final controller = RekaInboxController(
        repository: _FakeRepository(
          pending: [_row('shared', status: 'delivered')],
          recent: const [],
          offers: const [],
        ),
        observeNudgeStore: true,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
        baseUrl: 'https://inbox.test',
        enableLogging: false,
      );
      addTearDown(api.close);

      expect(controller.unreadCount, 1);
      expect(await store.outcome('shared', 'dismissed', api: api), isTrue);

      expect(controller.itemById('shared')?.status, 'dismissed');
      expect(controller.unreadCount, 0);
    });

    test(
      'shared Home outcome overlays a stale load that completes later',
      () async {
        final store = RekaNudges.instance;
        store.reset();
        addTearDown(store.reset);
        store.pushArrival(
          const RekaNudge(id: 'shared', text: '共享提醒', status: 'delivered'),
        );
        final pendingLoad = Completer<List<Map<String, dynamic>>>();
        final repository = _PendingRepository(pendingLoad);
        final controller = RekaInboxController(
          repository: repository,
          observeNudgeStore: true,
        );
        addTearDown(controller.dispose);
        final load = controller.load(includeOffers: false);
        final api = ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'nudge': {'status': 'acted'},
              }),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
          baseUrl: 'https://inbox.test',
          enableLogging: false,
        );
        addTearDown(api.close);

        expect(await store.outcome('shared', 'acted', api: api), isTrue);
        pendingLoad.complete([_row('shared', status: 'delivered')]);
        await load;

        expect(controller.itemById('shared')?.status, 'acted');
        expect(controller.unreadCount, 0);
      },
    );

    test('offer revival is observed before recent history is merged', () async {
      final repository = _RevivedOfferRepository();
      final controller = RekaInboxController(repository: repository);

      await controller.load();

      expect(repository.recentLoadedAfterOffer, isTrue);
      expect(controller.itemById('revived')?.status, 'pending');
      expect(controller.unreadCount, 1);
    });

    test('a live REKA arrival refreshes the data-backed badge', () async {
      final store = RekaNudges.instance;
      store.reset();
      addTearDown(store.reset);
      final pending = <Map<String, dynamic>>[];
      final controller = RekaInboxController(
        repository: _FakeRepository(
          pending: pending,
          recent: const [],
          offers: const [],
        ),
        observeNudgeStore: true,
      );
      addTearDown(controller.dispose);
      await controller.load(includeOffers: false);
      expect(controller.unreadCount, 0);

      pending.add(_row('arrival', status: 'delivered'));
      store.pushArrival(
        const RekaNudge(id: 'arrival', text: '新到提醒', status: 'delivered'),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.itemById('arrival'), isNotNull);
      expect(controller.unreadCount, 1);

      store.reset();
      expect(controller.items, isEmpty);
      expect(controller.unreadCount, 0);
    });

    test(
      'a committed shared status becomes the next rollback baseline',
      () async {
        final store = RekaNudges.instance;
        store.reset();
        addTearDown(store.reset);
        store.pushArrival(
          const RekaNudge(id: 'shared', text: '共享提醒', status: 'delivered'),
        );
        final repository = _FakeRepository(
          pending: [_row('shared', status: 'delivered')],
          recent: const [],
          offers: const [],
        );
        final controller = RekaInboxController(
          repository: repository,
          observeNudgeStore: true,
        );
        addTearDown(controller.dispose);
        await controller.load();
        final api = ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'ok': true}),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
          baseUrl: 'https://inbox.test',
          enableLogging: false,
        );
        addTearDown(api.close);

        expect(await store.outcome('shared', 'seen', api: api), isTrue);
        expect(controller.itemById('shared')?.status, 'seen');
        repository.outcomeError = StateError('offline');

        expect(await controller.markActed('shared'), isFalse);
        expect(controller.itemById('shared')?.status, 'seen');
      },
    );
  });

  test(
    'API repository adapts Theme V2 notifications without legacy nudge APIs',
    () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'notifications': [
              {
                'id': 'notification-1',
                'type': 'flash_done',
                'title': '闪念已整理',
                'body': '已提取 1 条待办',
                'link': '/library?recording_id=recording-1',
                'read': false,
                'created_at': '2026-08-03T02:00:00Z',
              },
            ],
            'unread': 1,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      final api = ApiClient(
        client: client,
        baseUrl: 'https://inbox.test',
        enableLogging: false,
      );
      addTearDown(api.close);
      final repository = ApiRekaInboxRepository(api);

      final items = await repository.loadPending();
      expect(items, hasLength(1));
      expect(items.single, containsPair('text', '闪念已整理'));
      expect(items.single, containsPair('cta', 'notification'));
      expect(items.single, containsPair('status', 'pending'));
      expect(await repository.loadRecent(), isEmpty);
      expect(await repository.loadOffers(), isEmpty);
      await repository.outcome('notification-1', 'seen');

      expect(calls, [
        'GET /api/notifications',
        'POST /api/notifications/notification-1/read',
      ]);
    },
  );

  test('dismissing a report notification also dismisses its trigger', () async {
    final calls = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 'notification-report',
                  'type': 'report_available',
                  'title': '需要准备会前调研吗？',
                  'body': '',
                  'link': 'report-start:execution-1:1',
                  'read': false,
                  'created_at': '2026-08-03T02:00:00Z',
                },
              ],
              'unread': 1,
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'https://inbox.test',
      enableLogging: false,
    );
    addTearDown(api.close);
    final repository = ApiRekaInboxRepository(api);

    await repository.loadPending();
    await repository.outcome('notification-report', 'dismissed');

    expect(calls, [
      'GET /api/notifications',
      'POST /api/trigger-executions/execution-1/dismiss',
      'DELETE /api/notifications/notification-report',
    ]);
  });

  test(
    'shared outcome adopts the backend authoritative terminal status',
    () async {
      final store = RekaNudges.instance;
      store.reset();
      addTearDown(store.reset);
      store.pushArrival(
        const RekaNudge(id: 'shared', text: '共享提醒', status: 'delivered'),
      );
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'nudge': {'status': 'acted'},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
        baseUrl: 'https://inbox.test',
        enableLogging: false,
      );
      addTearDown(api.close);

      expect(await store.outcome('shared', 'seen', api: api), isTrue);

      expect(store.latestOutcome?.status, 'acted');
      expect(store.latestOutcome?.committed, isTrue);
      expect(store.pending.where((item) => item.id == 'shared'), isEmpty);
    },
  );

  test(
    'older same-id outcome completion cannot overwrite a newer outcome',
    () async {
      final store = RekaNudges.instance;
      store.reset();
      addTearDown(store.reset);
      store.pushArrival(
        const RekaNudge(id: 'shared', text: '共享提醒', status: 'delivered'),
      );
      final seen = Completer<http.Response>();
      final acted = Completer<http.Response>();
      final api = ApiClient(
        client: MockClient((request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return body['status'] == 'seen' ? seen.future : acted.future;
        }),
        baseUrl: 'https://inbox.test',
        enableLogging: false,
      );
      addTearDown(api.close);

      final seenOutcome = store.outcome('shared', 'seen', api: api);
      final actedOutcome = store.outcome('shared', 'acted', api: api);
      acted.complete(
        http.Response(
          jsonEncode({
            'ok': true,
            'nudge': {'status': 'acted'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );
      expect(await actedOutcome, isTrue);
      seen.complete(
        http.Response(
          jsonEncode({
            'ok': true,
            'nudge': {'status': 'acted'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );
      expect(await seenOutcome, isTrue);

      expect(store.latestOutcome?.status, 'acted');
      expect(store.latestOutcome?.committed, isTrue);
      expect(store.pending.where((item) => item.id == 'shared'), isEmpty);
    },
  );
}

Map<String, dynamic> _row(
  String id, {
  String status = 'pending',
  int minute = 0,
}) => {
  'id': id,
  'type': 'nudge',
  'kind': id == 'offer' ? 'offer' : 'overdue',
  'text': '提醒 $id',
  'body': '正文 $id',
  'ref': 'todo:$id',
  'cta': 'view',
  'status': status,
  'created_at': DateTime.utc(2026, 7, 28, 2, minute).toIso8601String(),
};

class _FakeRepository implements RekaInboxRepository {
  _FakeRepository({
    required this.pending,
    required this.recent,
    required this.offers,
  });

  final List<Map<String, dynamic>> pending;
  final List<Map<String, dynamic>> recent;
  final List<Map<String, dynamic>> offers;
  Object? pendingError;
  Object? recentError;
  Object? offersError;
  Object? outcomeError;
  int offerLoads = 0;
  final List<(String, String)> outcomes = [];

  @override
  Future<List<Map<String, dynamic>>> loadPending() async {
    if (pendingError case final error?) throw error;
    return pending;
  }

  @override
  Future<List<Map<String, dynamic>>> loadRecent() async {
    if (recentError case final error?) throw error;
    return recent;
  }

  @override
  Future<List<Map<String, dynamic>>> loadOffers() async {
    offerLoads++;
    if (offersError case final error?) throw error;
    return offers;
  }

  @override
  Future<void> outcome(String id, String status) async {
    outcomes.add((id, status));
    if (outcomeError case final error?) throw error;
  }
}

class _SequenceRepository extends _FakeRepository {
  _SequenceRepository()
    : super(pending: [_row('ready')], recent: const [], offers: const []);

  bool fail = true;

  @override
  Future<List<Map<String, dynamic>>> loadPending() async {
    if (fail) throw StateError('offline');
    return super.loadPending();
  }

  @override
  Future<List<Map<String, dynamic>>> loadRecent() async {
    if (fail) throw StateError('offline');
    return super.loadRecent();
  }

  @override
  Future<List<Map<String, dynamic>>> loadOffers() async {
    if (fail) throw StateError('offline');
    return super.loadOffers();
  }
}

class _PendingRepository extends _FakeRepository {
  _PendingRepository(this.pendingLoad)
    : super(pending: const [], recent: const [], offers: const []);

  final Completer<List<Map<String, dynamic>>> pendingLoad;

  @override
  Future<List<Map<String, dynamic>>> loadPending() => pendingLoad.future;
}

class _RevivedOfferRepository extends _FakeRepository {
  _RevivedOfferRepository()
    : super(pending: const [], recent: const [], offers: const []);

  bool _offerLoaded = false;
  bool recentLoadedAfterOffer = false;

  @override
  Future<List<Map<String, dynamic>>> loadOffers() async {
    _offerLoaded = true;
    return [_row('revived', status: 'pending')];
  }

  @override
  Future<List<Map<String, dynamic>>> loadRecent() async {
    recentLoadedAfterOffer = _offerLoaded;
    return [_row('revived', status: _offerLoaded ? 'pending' : 'dismissed')];
  }
}

class _ControlledOutcomeRepository extends _FakeRepository {
  _ControlledOutcomeRepository({required super.pending})
    : super(recent: const [], offers: const []);

  final List<Completer<void>> pendingOutcomes = [];

  @override
  Future<void> outcome(String id, String status) {
    outcomes.add((id, status));
    final completer = Completer<void>();
    pendingOutcomes.add(completer);
    return completer.future;
  }
}
