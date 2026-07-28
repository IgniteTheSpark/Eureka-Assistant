import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/assets/assets.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme_v2/library/library_controller.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('LibraryController', () {
    test(
      'loads one aggregate snapshot and restores persisted pinned order',
      () async {
        final repository = _FakeRepository(_snapshot());
        final store = _MemoryPinnedStore(['notes', 'todo']);
        final controller = LibraryController(
          repository: repository,
          pinnedStore: store,
        );

        await controller.load();

        expect(repository.loadCount, 1);
        expect(controller.status, LibraryStatus.ready);
        expect(controller.pinnedContainers.map((item) => item.id), [
          'notes',
          'todo',
        ]);
        expect(controller.snapshot?.assetTotal, 9);
        expect(controller.snapshot?.containerCount, 5);
        expect(controller.snapshot?.activeSignalCount, 1);
      },
    );

    test(
      'expired persisted pins are removed without adding unselected defaults',
      () async {
        final controller = LibraryController(
          repository: _FakeRepository(_snapshot()),
          pinnedStore: _MemoryPinnedStore(['missing', 'notes']),
        );

        await controller.load();

        expect(controller.pinnedContainers.map((item) => item.id), ['notes']);
      },
    );

    test(
      'removed and explicitly empty pin selections survive reload',
      () async {
        final store = _MemoryPinnedStore();
        final first = LibraryController(
          repository: _FakeRepository(_snapshot()),
          pinnedStore: store,
        );
        await first.load();

        expect(first.pinnedContainers, isNotEmpty);
        await first.replacePinned(const []);

        final reloaded = LibraryController(
          repository: _FakeRepository(_snapshot()),
          pinnedStore: store,
        );
        await reloaded.load();

        expect(reloaded.pinnedContainers, isEmpty);
      },
    );

    test(
      'keeps successful sources visible when aggregate load is partial',
      () async {
        final controller = LibraryController(
          repository: _FakeRepository(
            _snapshot(failedSources: const {'contacts', 'reports'}),
          ),
          pinnedStore: _MemoryPinnedStore(),
        );

        await controller.load();

        expect(controller.status, LibraryStatus.partial);
        expect(controller.snapshot?.failedSources, {'contacts', 'reports'});
        expect(controller.containers, isNotEmpty);
        expect(controller.statusMessage, contains('部分内容'));
      },
    );

    test(
      'keeps partial state when every successful source is currently empty',
      () async {
        final controller = LibraryController(
          repository: _FakeRepository(
            const LibrarySnapshot(
              failedSources: {'assets', 'skills'},
              availableSources: {'reports'},
            ),
          ),
          pinnedStore: _MemoryPinnedStore(),
        );

        await controller.load();

        expect(controller.status, LibraryStatus.partial);
        expect(controller.containers, isEmpty);
        expect(controller.statusMessage, contains('部分内容'));
      },
    );

    test('shows offline error and retry replaces it with fresh data', () async {
      final repository = _SequenceRepository([
        const LibraryLoadFailure.offline(),
        _snapshot(),
      ]);
      final controller = LibraryController(
        repository: repository,
        pinnedStore: _MemoryPinnedStore(),
      );

      await controller.load();
      expect(controller.status, LibraryStatus.offline);
      expect(controller.containers, isEmpty);

      await controller.retry();
      expect(controller.status, LibraryStatus.ready);
      expect(controller.containers, isNotEmpty);
      expect(repository.loadCount, 2);
    });

    test(
      'stale overlapping load cannot replace a newer retry response',
      () async {
        final repository = _OverlappingRepository();
        final controller = LibraryController(
          repository: repository,
          pinnedStore: _MemoryPinnedStore(),
        );

        final first = controller.load();
        final second = controller.retry();
        repository.second.complete(_snapshot());
        await second;
        repository.first.complete(const LibrarySnapshot());
        await first;

        expect(controller.status, LibraryStatus.ready);
        expect(controller.containers, isNotEmpty);
      },
    );

    test('dispose invalidates a pending aggregate load', () async {
      final repository = _OverlappingRepository();
      final controller = LibraryController(
        repository: repository,
        pinnedStore: _MemoryPinnedStore(),
      );

      final load = controller.load();
      controller.dispose();
      repository.first.complete(_snapshot());

      await expectLater(load, completes);
    });

    test('dispose invalidates a pending failed pin save', () async {
      final store = _PendingPinnedStore();
      final controller = LibraryController(
        repository: _FakeRepository(_snapshot()),
        pinnedStore: store,
      );
      await controller.load();

      final save = controller.replacePinned(['notes', 'todo']);
      controller.dispose();
      store.pending.completeError(StateError('permission denied'));

      await expectLater(save, completion(isFalse));
    });

    test('zero containers is an explicit empty state', () async {
      final controller = LibraryController(
        repository: _FakeRepository(const LibrarySnapshot()),
        pinnedStore: _MemoryPinnedStore(),
      );

      await controller.load();

      expect(controller.status, LibraryStatus.empty);
      expect(controller.pinnedContainers, isEmpty);
    });

    test('query filters both system and custom container groups', () async {
      final controller = LibraryController(
        repository: _FakeRepository(_snapshot()),
        pinnedStore: _MemoryPinnedStore(),
      );
      await controller.load();

      controller.setQuery('网球');

      expect(controller.systemContainers, isEmpty);
      expect(controller.customContainers.map((item) => item.id), ['tennis']);
    });

    test('failed pinned persistence rolls optimistic order back', () async {
      final store = _MemoryPinnedStore(['todo', 'notes'])..failNextSave = true;
      final controller = LibraryController(
        repository: _FakeRepository(_snapshot()),
        pinnedStore: store,
      );
      await controller.load();

      final saved = await controller.replacePinned(['notes', 'todo']);

      expect(saved, isFalse);
      expect(controller.pinnedContainers.map((item) => item.id), [
        'todo',
        'notes',
      ]);
      expect(controller.pinSaveError, isNotNull);
      expect(store.savedOrders, isEmpty);
    });

    test('successful pinned reorder persists sanitized full order', () async {
      final store = _MemoryPinnedStore(['todo', 'notes']);
      final controller = LibraryController(
        repository: _FakeRepository(_snapshot()),
        pinnedStore: store,
      );
      await controller.load();

      final saved = await controller.replacePinned([
        'notes',
        'missing',
        'todo',
        'notes',
      ]);

      expect(saved, isTrue);
      expect(store.savedOrders.single, ['notes', 'todo']);
      expect(controller.pinnedContainers.map((item) => item.id), [
        'notes',
        'todo',
      ]);
    });

    test(
      'pinned domain caps persisted configuration at six containers',
      () async {
        final store = _MemoryPinnedStore();
        final controller = LibraryController(
          repository: _FakeRepository(
            LibrarySnapshot(
              skills: const {
                'one': SkillMeta('1', 'One', 'gray', '1'),
                'two': SkillMeta('2', 'Two', 'gray', '2'),
                'three': SkillMeta('3', 'Three', 'gray', '3'),
                'four': SkillMeta('4', 'Four', 'gray', '4'),
                'five': SkillMeta('5', 'Five', 'gray', '5'),
                'six': SkillMeta('6', 'Six', 'gray', '6'),
                'seven': SkillMeta('7', 'Seven', 'gray', '7'),
              },
              availableSources: const {'skills'},
            ),
          ),
          pinnedStore: store,
        );
        await controller.load();

        final saved = await controller.addPinned('seven');

        expect(saved, isFalse);
        expect(controller.pinnedContainers, hasLength(6));
        expect(controller.pinSaveError, contains('最多'));
        expect(store.savedOrders, isEmpty);
      },
    );

    test(
      'pin saves serialize and two failures roll back to disk state',
      () async {
        final store = _ControlledPinnedStore(['todo', 'notes']);
        final controller = LibraryController(
          repository: _FakeRepository(_snapshot()),
          pinnedStore: store,
        );
        await controller.load();

        final first = controller.replacePinned(['notes', 'todo']);
        final second = controller.replacePinned(['notes']);
        await Future<void>.delayed(Duration.zero);
        expect(store.pending, hasLength(1));

        store.pending[0].completeError(StateError('first failed'));
        await expectLater(first, completion(isFalse));
        await Future<void>.delayed(Duration.zero);
        expect(store.pending, hasLength(2));

        store.pending[1].completeError(StateError('second failed'));
        await expectLater(second, completion(isFalse));
        expect(controller.pinnedContainers.map((item) => item.id), [
          'todo',
          'notes',
        ]);
      },
    );

    test('an old failed pin save cannot overwrite a newer success', () async {
      final store = _ControlledPinnedStore(['todo', 'notes']);
      final controller = LibraryController(
        repository: _FakeRepository(_snapshot()),
        pinnedStore: store,
      );
      await controller.load();

      final first = controller.replacePinned(['notes', 'todo']);
      final second = controller.replacePinned(['notes']);
      await Future<void>.delayed(Duration.zero);
      store.pending[0].completeError(StateError('first failed'));
      await expectLater(first, completion(isFalse));
      await Future<void>.delayed(Duration.zero);

      store.pending[1].complete();
      await expectLater(second, completion(isTrue));
      expect(controller.pinnedContainers.map((item) => item.id), ['notes']);
    });
  });

  group('LibrarySnapshot aggregation', () {
    test(
      'preserves assets skills events contacts and reports in one model',
      () {
        final snapshot = _snapshot();

        expect(snapshot.assets, hasLength(2));
        expect(snapshot.skills.keys, containsAll(['todo', 'notes', 'tennis']));
        expect(snapshot.events, hasLength(1));
        expect(snapshot.contacts, hasLength(1));
        expect(snapshot.reports, hasLength(1));
        expect(snapshot.recentItems.map((item) => item.containerId), [
          'report',
          'contact',
          'event',
          'notes',
          'todo',
        ]);
        expect(
          snapshot.recentItems
              .singleWhere((item) => item.containerId == 'event')
              .id,
          'e1',
        );
      },
    );

    test(
      'shared card resolution preserves domain for direct recent detail',
      () {
        final card = resolveSkillCardData(const {
          'asset_id': 'a1',
          'user_skill_name': 'todo',
          'payload': {'title': '任务'},
          'domain': '工作',
        }, const {});

        expect(card.domain, '工作');
      },
    );
  });

  test(
    'API adapter requests each mature source once with real entity shapes',
    () async {
      final calls = <String, int>{};
      final client = MockClient((request) async {
        final path = request.url.path;
        calls.update(path, (count) => count + 1, ifAbsent: () => 1);
        final body = switch (path) {
          '/api/assets' => {
            'assets': [
              {
                'id': 'a1',
                'user_skill_name': 'todo',
                'payload': {'title': '任务'},
                'created_at': '2026-07-28T12:00:00',
              },
            ],
          },
          '/api/skills' => {
            'skills': [
              {
                'name': 'todo',
                'display_name': '待办',
                'user_skill_id': 's1',
                'enabled': 1,
                'render_spec': {'icon': '📋', 'accent_color': 'blue'},
              },
            ],
          },
          '/api/events' => {
            'events': [
              {
                'event_id': 'e1',
                'title': '评审',
                'created_at': '2026-07-28T11:00:00',
              },
            ],
          },
          '/api/contacts' => {
            'contacts': [
              {'id': 'c1', 'name': '小王', 'created_at': '2026-07-28T10:00:00'},
            ],
          },
          '/api/reports' => {
            'reports': [
              {'id': 'r1', 'title': '周报', 'created_at': '2026-07-28T09:00:00'},
            ],
          },
          '/api/assets/counts' => {
            'counts': {'todo': 7},
          },
          _ => throw StateError('unexpected $path'),
        };
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = ApiClient(
        client: client,
        baseUrl: 'https://library.test',
        enableLogging: false,
      );
      addTearDown(api.close);

      final snapshot = await ApiLibraryRepository(api).load();

      expect(calls, containsPair('/api/assets', 1));
      expect(calls.values, everyElement(1));
      expect(calls, hasLength(6));
      expect(snapshot.assetTotal, 7);
      expect(snapshot.skills.keys, contains('todo'));
      expect(
        snapshot.availableSources,
        containsAll(['skills', 'events', 'contacts']),
      );
      expect(snapshot.containerCount, 3);
      expect(
        snapshot.recentItems
            .singleWhere((item) => item.containerId == 'event')
            .id,
        'e1',
      );
      expect(
        snapshot.recentItems.map((item) => item.containerId),
        contains('report'),
      );
      expect(
        snapshot.containers.map((item) => item.id),
        isNot(contains('report')),
      );
    },
  );
}

LibrarySnapshot _snapshot({Set<String> failedSources = const {}}) {
  final now = DateTime(2026, 7, 28, 12);
  return LibrarySnapshot(
    assets: [
      AssetItem(
        id: 'a1',
        skillName: 'todo',
        payload: const {'title': '提交重构'},
        createdAt: now.subtract(const Duration(minutes: 8)),
      ),
      AssetItem(
        id: 'a2',
        skillName: 'notes',
        payload: const {'content': '交互记录'},
        createdAt: now.subtract(const Duration(minutes: 6)),
      ),
    ],
    skills: const {
      'todo': SkillMeta('📋', '待办', 'blue', 's-todo'),
      'notes': SkillMeta('✍️', '笔记', 'amber', 's-notes'),
      'tennis': SkillMeta('🎾', '网球记录', 'green', 's-tennis'),
    },
    events: [
      {
        'event_id': 'e1',
        'title': '设计评审',
        'created_at': now
            .subtract(const Duration(minutes: 4))
            .toIso8601String(),
      },
    ],
    contacts: [
      {
        'id': 'c1',
        'name': '王小明',
        'created_at': now
            .subtract(const Duration(minutes: 2))
            .toIso8601String(),
      },
    ],
    reports: [
      {
        'id': 'r1',
        'title': '周报',
        'created_at': now
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      },
    ],
    assetCounts: const {'todo': 4, 'notes': 3, 'tennis': 2},
    failedSources: failedSources,
    availableSources: {
      'assets',
      'skills',
      'events',
      'contacts',
      'reports',
      'counts',
    }..removeAll(failedSources),
  );
}

class _FakeRepository implements LibraryRepository {
  _FakeRepository(this.snapshot);

  final LibrarySnapshot snapshot;
  int loadCount = 0;

  @override
  Future<LibrarySnapshot> load() async {
    loadCount++;
    return snapshot;
  }
}

class _SequenceRepository implements LibraryRepository {
  _SequenceRepository(this.results);

  final List<Object> results;
  int loadCount = 0;

  @override
  Future<LibrarySnapshot> load() async {
    final result = results[loadCount++];
    if (result is LibraryLoadFailure) throw result;
    return result as LibrarySnapshot;
  }
}

class _MemoryPinnedStore implements LibraryPinnedStore {
  _MemoryPinnedStore([List<String>? initial])
    : value = initial == null ? null : List.of(initial);

  List<String>? value;
  final List<List<String>> savedOrders = [];
  bool failNextSave = false;

  @override
  Future<List<String>?> load() async =>
      value == null ? null : List<String>.of(value!);

  @override
  Future<void> save(List<String> ids) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('permission denied');
    }
    final saved = List<String>.of(ids);
    value = saved;
    savedOrders.add(saved);
  }
}

class _ControlledPinnedStore implements LibraryPinnedStore {
  _ControlledPinnedStore(this.initial);

  final List<String> initial;
  final List<Completer<void>> pending = [];

  @override
  Future<List<String>> load() async => List.of(initial);

  @override
  Future<void> save(List<String> ids) {
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  }
}

class _PendingPinnedStore implements LibraryPinnedStore {
  final pending = Completer<void>();

  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> save(List<String> ids) => pending.future;
}

class _OverlappingRepository implements LibraryRepository {
  final first = Completer<LibrarySnapshot>();
  final second = Completer<LibrarySnapshot>();
  int _calls = 0;

  @override
  Future<LibrarySnapshot> load() {
    _calls++;
    return _calls == 1 ? first.future : second.future;
  }
}
