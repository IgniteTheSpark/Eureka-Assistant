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
