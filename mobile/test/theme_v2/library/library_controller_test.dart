import 'dart:async';

import 'package:eureka/theme_v2/library/library_controller.dart';
import 'package:eureka/theme_v2/library/library_models.dart';
import 'package:eureka/theme_v2/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryController', () {
    test('loads one overview and restores a sanitized pinned order', () async {
      final repository = _Repository(_overview());
      final controller = LibraryController(
        repository: repository,
        pinnedStore: _PinnedStore(
          initial: ['notes', 'missing', 'todo', 'todo'],
        ),
      );

      await controller.load();

      expect(repository.loadCount, 1);
      expect(controller.status, LibraryStatus.ready);
      expect(controller.overview?.totalAssetCount, 7);
      expect(controller.pinnedContainers.map((item) => item.id), [
        'notes',
        'todo',
      ]);
    });

    test(
      'a missing preference uses defaults but an empty one stays empty',
      () async {
        final defaults = LibraryController(
          repository: _Repository(_overview()),
          pinnedStore: _PinnedStore(),
        );
        await defaults.load();
        expect(defaults.pinnedContainers, hasLength(5));

        final empty = LibraryController(
          repository: _Repository(_overview()),
          pinnedStore: _PinnedStore(initial: const []),
        );
        await empty.load();
        expect(empty.pinnedContainers, isEmpty);
      },
    );

    test(
      'directory queries are independent and clear without reload',
      () async {
        final repository = _Repository(_overview());
        final controller = LibraryController(
          repository: repository,
          pinnedStore: _PinnedStore(),
        );
        await controller.load();

        controller.setIndexQuery('网球');
        expect(controller.indexCustomContainers.map((item) => item.id), [
          'tennis',
        ]);
        expect(controller.allSystemContainers, hasLength(4));

        controller.setAllQuery('事件');
        expect(controller.allSystemContainers.map((item) => item.id), [
          'event',
        ]);
        expect(controller.indexQuery, '网球');

        controller.clearIndexQuery();
        expect(controller.indexCustomContainers, hasLength(1));
        expect(repository.loadCount, 1);
      },
    );

    test('partial empty and offline loads expose distinct states', () async {
      final partial = LibraryController(
        repository: _Repository(
          _overview(
            failedSources: const [
              LibrarySourceFailure(source: 'events', isOffline: true),
            ],
          ),
        ),
        pinnedStore: _PinnedStore(),
      );
      await partial.load();
      expect(partial.status, LibraryStatus.partial);
      expect(partial.statusMessage, contains('部分内容'));

      final empty = LibraryController(
        repository: _Repository(_emptyOverview()),
        pinnedStore: _PinnedStore(),
      );
      await empty.load();
      expect(empty.status, LibraryStatus.empty);

      final offline = LibraryController(
        repository: _SequenceRepository([
          const LibraryLoadFailure('网络不可用', isOffline: true),
          _overview(),
        ]),
        pinnedStore: _PinnedStore(),
      );
      await offline.load();
      expect(offline.status, LibraryStatus.offline);
      await offline.retry();
      expect(offline.status, LibraryStatus.ready);
    });

    test('failed pinned save restores the latest confirmed order', () async {
      final store = _PinnedStore(initial: ['todo', 'notes'])..failNext = true;
      final controller = await _loadedController(store: store);

      final saving = controller.replacePinned(['notes', 'todo']);
      expect(controller.pinnedContainers.map((item) => item.id), [
        'notes',
        'todo',
      ]);
      expect(controller.isSavingPins, isTrue);

      expect(await saving, isFalse);
      expect(controller.pinnedContainers.map((item) => item.id), [
        'todo',
        'notes',
      ]);
      expect(controller.pinSaveError, contains('保存失败，已恢复原配置'));
      expect(controller.isSavingPins, isFalse);
    });

    test(
      'optimistic pin saves serialize and preserve the newest order',
      () async {
        final store = _PendingPinnedStore(['todo', 'notes']);
        final controller = LibraryController(
          repository: _Repository(_overview()),
          pinnedStore: store,
        );
        await controller.load();

        final first = controller.replacePinned(['notes', 'todo']);
        final second = controller.replacePinned(['event', 'notes']);
        await Future<void>.delayed(Duration.zero);

        expect(store.saved, [
          ['notes', 'todo'],
        ]);
        expect(controller.pinnedContainers.map((item) => item.id), [
          'event',
          'notes',
        ]);

        store.pending.removeAt(0).complete();
        await Future<void>.delayed(Duration.zero);
        expect(store.saved, [
          ['notes', 'todo'],
          ['event', 'notes'],
        ]);
        store.pending.removeAt(0).complete();

        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(controller.isSavingPins, isFalse);
        expect(controller.pinnedContainers.map((item) => item.id), [
          'event',
          'notes',
        ]);
      },
    );

    test('pins are unique valid and capped at six', () async {
      final overview = LibraryOverview(
        systemContainers: _systemContainers(),
        customContainers: [
          _summary('one', LibraryContainerType.custom, system: false),
          _summary('two', LibraryContainerType.custom, system: false),
          _summary('three', LibraryContainerType.custom, system: false),
        ],
      );
      final store = _PinnedStore(initial: const []);
      final controller = LibraryController(
        repository: _Repository(overview),
        pinnedStore: store,
      );
      await controller.load();

      expect(
        await controller.replacePinned([
          'todo',
          'notes',
          'event',
          'contact',
          'one',
          'two',
          'three',
          'one',
          'missing',
        ]),
        isTrue,
      );
      expect(controller.pinnedContainers, hasLength(6));
      expect(await controller.addPinned('three'), isFalse);
      expect(controller.pinSaveError, contains('最多'));
    });

    test('a stale load cannot replace a newer retry', () async {
      final repository = _OverlappingRepository();
      final controller = LibraryController(
        repository: repository,
        pinnedStore: _PinnedStore(),
      );

      final first = controller.load();
      final second = controller.retry();
      repository.second.complete(_overview());
      await second;
      repository.first.complete(_emptyOverview());
      await first;

      expect(controller.status, LibraryStatus.ready);
      expect(controller.overview?.customContainers, hasLength(1));
    });

    test('dispose invalidates pending loads and saves', () async {
      final repository = _OverlappingRepository();
      final store = _PendingPinnedStore(['todo']);
      final controller = LibraryController(
        repository: repository,
        pinnedStore: store,
      );

      final load = controller.load();
      controller.dispose();
      repository.first.complete(_overview());
      await expectLater(load, completes);

      final loaded = await _loadedController(
        store: _PinnedStore(initial: ['todo']),
      );
      loaded.dispose();
      expect(await loaded.replacePinned(['notes']), isFalse);
    });
  });
}

class _Repository implements LibraryRepository {
  _Repository(this.value);

  final LibraryOverview value;
  int loadCount = 0;

  @override
  Future<LibraryOverview> loadOverview() async {
    loadCount++;
    return value;
  }
}

class _SequenceRepository implements LibraryRepository {
  _SequenceRepository(this.values);

  final List<Object> values;

  @override
  Future<LibraryOverview> loadOverview() async {
    final value = values.removeAt(0);
    if (value is LibraryOverview) return value;
    throw value;
  }
}

class _OverlappingRepository implements LibraryRepository {
  final first = Completer<LibraryOverview>();
  final second = Completer<LibraryOverview>();
  var loadCount = 0;

  @override
  Future<LibraryOverview> loadOverview() {
    loadCount++;
    return loadCount == 1 ? first.future : second.future;
  }
}

class _PinnedStore implements LibraryPinnedStore {
  _PinnedStore({this.initial});

  final List<String>? initial;
  bool failNext = false;
  final List<List<String>> saved = [];

  @override
  Future<List<String>?> load() async =>
      initial == null ? null : List.of(initial!);

  @override
  Future<void> save(List<String> ids) async {
    if (failNext) {
      failNext = false;
      throw StateError('save denied');
    }
    saved.add(List.of(ids));
  }
}

class _PendingPinnedStore implements LibraryPinnedStore {
  _PendingPinnedStore(this.initial);

  final List<String> initial;
  final List<List<String>> saved = [];
  final List<Completer<void>> pending = [];

  @override
  Future<List<String>?> load() async => List.of(initial);

  @override
  Future<void> save(List<String> ids) {
    saved.add(List.of(ids));
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  }
}

LibraryContainerSummary _summary(
  String id,
  LibraryContainerType type, {
  int total = 1,
  bool system = true,
}) => LibraryContainerSummary(
  id: id,
  label: switch (id) {
    'todo' => '待办',
    'notes' => '随记',
    'event' => '事件',
    'contact' => '联系人',
    'tennis' => '网球',
    _ => id,
  },
  mark: '•',
  type: type,
  totalCount: total,
  isSystem: system,
);

List<LibraryContainerSummary> _systemContainers({int total = 1}) => [
  _summary('todo', LibraryContainerType.todo, total: total),
  _summary('notes', LibraryContainerType.notes, total: total),
  _summary('event', LibraryContainerType.event, total: total),
  _summary('contact', LibraryContainerType.contact, total: total),
];

LibraryOverview _overview({
  List<LibrarySourceFailure> failedSources = const [],
}) => LibraryOverview(
  systemContainers: _systemContainers(),
  customContainers: [
    _summary('tennis', LibraryContainerType.custom, total: 3, system: false),
  ],
  recentAssets: [
    LibraryRecentAsset(
      id: 'asset-1',
      skillName: 'tennis',
      skillLabel: '网球',
      mark: '🎾',
      primaryValue: '正手训练',
      createdAt: DateTime(2026, 7, 29),
      detailCard: const {},
    ),
  ],
  totalAssetCount: 7,
  failedSources: failedSources,
);

LibraryOverview _emptyOverview() =>
    LibraryOverview(systemContainers: _systemContainers(total: 0));

Future<LibraryController> _loadedController({
  required LibraryPinnedStore store,
}) async {
  final controller = LibraryController(
    repository: _Repository(_overview()),
    pinnedStore: store,
  );
  await controller.load();
  return controller;
}
