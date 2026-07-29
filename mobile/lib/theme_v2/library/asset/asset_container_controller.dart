import 'package:flutter/foundation.dart';

import 'asset_record.dart';

enum AssetContainerLoadState { idle, loading, ready, error }

@immutable
class AssetContainerPage {
  const AssetContainerPage({required this.records, this.nextCursor});

  final List<AssetRecordViewModel> records;
  final String? nextCursor;
}

abstract interface class AssetContainerRepository {
  Future<AssetContainerPage> load({String? cursor});

  Future<void> setTodoCompleted(String id, bool completed);
}

class AssetContainerController extends ChangeNotifier {
  AssetContainerController({
    required this.repository,
    required this.containerId,
    DateTime Function()? today,
    List<AssetRecordViewModel> initialRecords = const [],
  }) : _today = today ?? DateTime.now,
       _records = List.of(initialRecords);

  final AssetContainerRepository repository;
  final String containerId;
  final DateTime Function() _today;
  final Map<TodoAssetFilter, double> _offsets = {
    for (final filter in TodoAssetFilter.values) filter: 0,
  };

  List<AssetRecordViewModel> _records;
  TodoAssetFilter _filter = TodoAssetFilter.all;
  AssetContainerLoadState _loadState = AssetContainerLoadState.idle;
  String? _nextCursor;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _disposed = false;
  String? _errorMessage;
  String? _paginationError;

  bool get isTodo => containerId == 'todo';
  TodoAssetFilter get filter => _filter;
  AssetContainerLoadState get loadState => _loadState;
  bool get refreshing => _refreshing;
  bool get loadingMore => _loadingMore;
  String? get errorMessage => _errorMessage;
  String? get paginationError => _paginationError;
  bool get canLoadMore => _nextCursor != null && !_loadingMore;
  double get currentScrollOffset => _offsets[_filter] ?? 0;

  List<AssetRecordViewModel> get records {
    final visible = isTodo
        ? _records
              .where((record) => matchesTodoFilter(record, _filter, _today()))
              .toList()
        : List<AssetRecordViewModel>.of(_records);
    if (isTodo) return sortTodoRecords(visible);
    visible.sort((a, b) {
      final byDate = b.effectiveAt.compareTo(a.effectiveAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return List.unmodifiable(visible);
  }

  AssetRecordViewModel? record(String id) {
    for (final record in _records) {
      if (record.id == id) return record;
    }
    return null;
  }

  int countFor(TodoAssetFilter filter) {
    if (!isTodo) return _records.length;
    return _records
        .where((record) => matchesTodoFilter(record, filter, _today()))
        .length;
  }

  Future<void> load() async {
    if (_loadState == AssetContainerLoadState.loading) return;
    _loadState = AssetContainerLoadState.loading;
    _errorMessage = null;
    _notify();
    try {
      final page = await repository.load();
      if (_disposed) return;
      _records = List.of(page.records);
      _nextCursor = page.nextCursor;
      _loadState = AssetContainerLoadState.ready;
    } catch (_) {
      if (_disposed) return;
      _loadState = AssetContainerLoadState.error;
      _errorMessage = '内容暂时无法加载';
    }
    _notify();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    _errorMessage = null;
    _notify();
    try {
      final page = await repository.load();
      if (_disposed) return;
      _records = List.of(page.records);
      _nextCursor = page.nextCursor;
      _loadState = AssetContainerLoadState.ready;
    } catch (_) {
      if (_disposed) return;
      _errorMessage = '内容暂时无法刷新';
      if (_records.isEmpty) _loadState = AssetContainerLoadState.error;
    } finally {
      if (!_disposed) {
        _refreshing = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    _loadingMore = true;
    _paginationError = null;
    _notify();
    try {
      final page = await repository.load(cursor: cursor);
      if (_disposed) return;
      final byId = {for (final record in _records) record.id: record};
      for (final record in page.records) {
        byId[record.id] = record;
      }
      _records = byId.values.toList();
      _nextCursor = page.nextCursor;
    } catch (_) {
      if (_disposed) return;
      _paginationError = '更多内容暂时无法加载';
    } finally {
      if (!_disposed) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  void selectTodoFilter(TodoAssetFilter value) {
    if (!isTodo || value == _filter) return;
    _filter = value;
    _notify();
  }

  void rememberOffset(double value) {
    if (!value.isFinite || value < 0) return;
    _offsets[_filter] = value;
  }

  Future<void> toggleTodo(String id) async {
    final index = _records.indexWhere((record) => record.id == id);
    if (index < 0 || _records[index].kind != AssetRecordKind.todo) return;
    final previous = _records[index];
    final completed = !previous.completed;
    _records[index] = previous.copyWith(
      completed: completed,
      payload: {...previous.payload, 'status': completed ? 'done' : 'pending'},
    );
    _errorMessage = null;
    _notify();
    try {
      await repository.setTodoCompleted(id, completed);
    } catch (_) {
      if (!_disposed) {
        final rollbackIndex = _records.indexWhere((record) => record.id == id);
        if (rollbackIndex >= 0) _records[rollbackIndex] = previous;
        _errorMessage = '完成状态未保存，请重试';
        _notify();
      }
      rethrow;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
