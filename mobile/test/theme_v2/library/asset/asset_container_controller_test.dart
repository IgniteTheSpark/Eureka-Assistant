import 'dart:async';

import 'package:eureka/theme_v2/library/asset/asset_container_controller.dart';
import 'package:eureka/theme_v2/library/asset/asset_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Todo filters preserve independent offsets and expose counts', () async {
    final repository = _FakeAssetContainerRepository([
      _todo('today', dueAt: DateTime(2026, 7, 29, 18)),
      _todo('done', dueAt: DateTime(2026, 7, 28), completed: true),
      _todo('open', dueAt: null),
    ]);
    final controller = AssetContainerController(
      repository: repository,
      containerId: 'todo',
      today: () => DateTime(2026, 7, 29, 12),
    );
    addTearDown(controller.dispose);

    await controller.load();
    controller.rememberOffset(120);
    controller.selectTodoFilter(TodoAssetFilter.today);
    controller.rememberOffset(48);
    controller.selectTodoFilter(TodoAssetFilter.all);

    expect(controller.currentScrollOffset, 120);
    expect(controller.countFor(TodoAssetFilter.all), 3);
    expect(controller.countFor(TodoAssetFilter.today), 1);
    expect(controller.countFor(TodoAssetFilter.completed), 1);
    expect(controller.countFor(TodoAssetFilter.unscheduled), 1);
    expect(controller.records.map((record) => record.id), [
      'done',
      'today',
      'open',
    ]);
  });

  test('refresh keeps visible records until replacement arrives', () async {
    final first = _todo('first', dueAt: null);
    final next = _todo('next', dueAt: null);
    final repository = _FakeAssetContainerRepository([first]);
    final controller = AssetContainerController(
      repository: repository,
      containerId: 'todo',
    );
    addTearDown(controller.dispose);

    await controller.load();
    repository
      ..records = [next]
      ..blockNextLoad();
    final refresh = controller.refresh();

    expect(controller.refreshing, isTrue);
    expect(controller.records.single.id, 'first');
    repository.completeBlockedLoad();
    await refresh;
    expect(controller.records.single.id, 'next');
  });

  test(
    'refresh requested during refresh runs once more with latest data',
    () async {
      final repository = _ControlledAssetContainerRepository();
      final controller = AssetContainerController(
        repository: repository,
        containerId: 'notes',
        initialRecords: [_todo('cached', dueAt: null)],
      );
      addTearDown(controller.dispose);

      final catchUp = controller.refresh();
      final mutation = controller.refresh();
      expect(repository.requests, hasLength(1));

      repository.complete(0, [_todo('before-mutation', dueAt: null)]);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests, hasLength(2));
      repository.complete(1, [_todo('after-mutation', dueAt: null)]);

      await Future.wait([catchUp, mutation]);
      expect(controller.records.single.id, 'after-mutation');
    },
  );

  test(
    'refresh waits for initial load before reconciling newer data',
    () async {
      final repository = _ControlledAssetContainerRepository();
      final controller = AssetContainerController(
        repository: repository,
        containerId: 'notes',
      );
      addTearDown(controller.dispose);

      final initialLoad = controller.load();
      final catchUp = controller.refresh();
      expect(repository.requests, hasLength(1));

      repository.complete(0, [_todo('initial-snapshot', dueAt: null)]);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests, hasLength(2));
      repository.complete(1, [_todo('reconciled-snapshot', dueAt: null)]);

      await Future.wait([initialLoad, catchUp]);
      expect(controller.records.single.id, 'reconciled-snapshot');
    },
  );

  test('refresh invalidates an older in-flight pagination response', () async {
    final repository = _ControlledAssetContainerRepository();
    final controller = AssetContainerController(
      repository: repository,
      containerId: 'notes',
    );
    addTearDown(controller.dispose);

    final initialLoad = controller.load();
    repository.complete(0, [_todo('initial', dueAt: null)], nextCursor: 'next');
    await initialLoad;

    final pagination = controller.loadMore();
    expect(repository.requests[1].cursor, 'next');
    final catchUp = controller.refresh();
    expect(repository.requests[2].cursor, isNull);
    repository.complete(2, [_todo('reconciled', dueAt: null)]);
    await catchUp;

    repository.complete(1, [
      _todo('stale-page', dueAt: null),
    ], nextCursor: 'stale-next');
    await pagination;

    expect(controller.records.map((record) => record.id), ['reconciled']);
    expect(controller.canLoadMore, isFalse);
  });

  test(
    'failed optimistic completion restores only the changed record',
    () async {
      final repository = _FakeAssetContainerRepository([
        _todo('a', dueAt: null),
        _todo('b', dueAt: null),
      ])..completeError = StateError('offline');
      final controller = AssetContainerController(
        repository: repository,
        containerId: 'todo',
      );
      addTearDown(controller.dispose);

      await controller.load();
      final future = controller.toggleTodo('a');
      expect(controller.record('a')?.completed, isTrue);
      expect(controller.record('b')?.completed, isFalse);
      await expectLater(future, throwsStateError);

      expect(controller.record('a')?.completed, isFalse);
      expect(controller.record('b')?.completed, isFalse);
      expect(controller.errorMessage, '完成状态未保存，请重试');
    },
  );

  test('pagination failure keeps loaded records and can retry', () async {
    final repository = _FakeAssetContainerRepository([
      _todo('first', dueAt: null),
    ], nextCursor: 'next');
    final controller = AssetContainerController(
      repository: repository,
      containerId: 'todo',
    );
    addTearDown(controller.dispose);
    await controller.load();

    repository.loadMoreError = StateError('offline');
    await controller.loadMore();

    expect(controller.records.single.id, 'first');
    expect(controller.paginationError, '更多内容暂时无法加载');

    repository
      ..loadMoreError = null
      ..records = [_todo('second', dueAt: null)]
      ..nextCursor = null;
    await controller.loadMore();
    expect(controller.records.map((record) => record.id), ['second', 'first']);
    expect(controller.paginationError, isNull);
  });
}

class _FakeAssetContainerRepository implements AssetContainerRepository {
  _FakeAssetContainerRepository(this.records, {this.nextCursor});

  List<AssetRecordViewModel> records;
  String? nextCursor;
  Object? completeError;
  Object? loadMoreError;
  bool _blocked = false;
  Completer<void>? _loadCompleter;

  void blockNextLoad() {
    _blocked = true;
    _loadCompleter = Completer<void>();
  }

  void completeBlockedLoad() => _loadCompleter?.complete();

  @override
  Future<AssetContainerPage> load({String? cursor}) async {
    if (_blocked) {
      await _loadCompleter!.future;
      _blocked = false;
    }
    if (cursor != null && loadMoreError != null) throw loadMoreError!;
    return AssetContainerPage(records: records, nextCursor: nextCursor);
  }

  @override
  Future<void> setTodoCompleted(String id, bool completed) async {
    if (completeError != null) throw completeError!;
  }
}

class _ControlledAssetContainerRepository implements AssetContainerRepository {
  final requests = <_ControlledLoad>[];

  void complete(
    int index,
    List<AssetRecordViewModel> records, {
    String? nextCursor,
  }) {
    requests[index].completer.complete(
      AssetContainerPage(records: records, nextCursor: nextCursor),
    );
  }

  @override
  Future<AssetContainerPage> load({String? cursor}) {
    final request = _ControlledLoad(cursor);
    requests.add(request);
    return request.completer.future;
  }

  @override
  Future<void> setTodoCompleted(String id, bool completed) async {}
}

class _ControlledLoad {
  _ControlledLoad(this.cursor);

  final String? cursor;
  final completer = Completer<AssetContainerPage>();
}

AssetRecordViewModel _todo(
  String id, {
  required DateTime? dueAt,
  bool completed = false,
}) {
  return AssetRecordViewModel(
    id: id,
    containerId: 'todo',
    kind: AssetRecordKind.todo,
    card: AssetRecordCard(mark: '✓', skillLabel: '待办', primaryValue: id),
    fields: const [],
    payload: {'title': id, 'status': completed ? 'done' : 'pending'},
    createdAt: DateTime(2026, 7, 28),
    dueAt: dueAt,
    completed: completed,
  );
}
