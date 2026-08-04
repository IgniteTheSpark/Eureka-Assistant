import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_models.dart';
import 'library_repository.dart';

enum LibraryStatus { idle, loading, ready, partial, empty, offline, error }

abstract interface class LibraryPinnedStore {
  Future<List<String>?> load();
  Future<void> save(List<String> ids);
}

class SharedPreferencesLibraryPinnedStore implements LibraryPinnedStore {
  const SharedPreferencesLibraryPinnedStore();

  static const _legacyKey = 'theme_v2.library.pinned_order';
  static const _key = 'theme_v2.library.pinned_order.v2_reports';
  static const _reportId = 'system:report';

  @override
  Future<List<String>?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_key);
    if (current != null) return current;
    final legacy = preferences.getStringList(_legacyKey);
    if (legacy == null) return null;
    final migrated = legacy.isEmpty
        ? <String>[]
        : <String>[...legacy.where((id) => id != _reportId).take(5), _reportId];
    final saved = await preferences.setStringList(_key, migrated);
    if (!saved) throw StateError('无法迁移常驻容器配置');
    return migrated;
  }

  @override
  Future<void> save(List<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setStringList(_key, ids);
    if (!saved) throw StateError('无法保存常驻容器配置');
  }
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.repository,
    this.pinnedStore = const SharedPreferencesLibraryPinnedStore(),
  });

  final LibraryRepository repository;
  final LibraryPinnedStore pinnedStore;

  LibraryStatus _status = LibraryStatus.idle;
  LibraryOverview? _overview;
  String _indexQuery = '';
  String _allQuery = '';
  String? _errorMessage;
  String? _pinSaveError;
  List<String> _pinnedIds = const [];
  List<String> _confirmedPinnedIds = const [];
  Future<void> _pinSaveTail = Future<void>.value();
  int _pendingPinSaves = 0;
  int _pinSaveRevision = 0;
  int _loadRevision = 0;
  bool _disposed = false;

  LibraryStatus get status => _status;
  LibraryOverview? get overview => _overview;
  String get indexQuery => _indexQuery;
  String get allQuery => _allQuery;
  String? get errorMessage => _errorMessage;
  String? get pinSaveError => _pinSaveError;
  bool get isLoading => _status == LibraryStatus.loading;
  bool get isSavingPins => _pendingPinSaves > 0;
  bool get canPinMore => _pinnedIds.length < 6;

  String? get statusMessage =>
      _status == LibraryStatus.partial ? '部分内容加载失败，可重试刷新' : null;

  List<LibraryContainerSummary> get containers =>
      _overview?.containers ?? const [];

  List<LibraryContainerSummary> get indexSystemContainers =>
      _filter(_overview?.systemContainers ?? const [], _indexQuery);

  List<LibraryContainerSummary> get indexCustomContainers =>
      _filter(_overview?.customContainers ?? const [], _indexQuery);

  List<LibraryContainerSummary> get allSystemContainers =>
      _filter(_overview?.systemContainers ?? const [], _allQuery);

  List<LibraryContainerSummary> get allCustomContainers =>
      _filter(_overview?.customContainers ?? const [], _allQuery);

  List<LibraryContainerSummary> get pinnedContainers {
    final byId = {for (final container in containers) container.id: container};
    return [for (final id in _pinnedIds) ?byId[id]];
  }

  List<LibraryContainerSummary> get availableToPin {
    final pinned = _pinnedIds.toSet();
    return [
      for (final container in containers)
        if (!pinned.contains(container.id)) container,
    ];
  }

  Future<void> load() async {
    if (_disposed) return;
    final revision = ++_loadRevision;
    _status = LibraryStatus.loading;
    _errorMessage = null;
    _notify();
    try {
      final next = await repository.loadOverview();
      if (!_isCurrentLoad(revision)) return;
      await _pinSaveTail;
      if (!_isCurrentLoad(revision)) return;

      List<String>? persisted;
      try {
        persisted = await pinnedStore.load();
      } catch (error) {
        _pinSaveError = '无法读取常驻配置：$error';
      }
      if (!_isCurrentLoad(revision)) return;

      _overview = next;
      final defaults = next.containers.map((container) => container.id);
      _pinnedIds = _sanitizePinned(persisted ?? defaults);
      _confirmedPinnedIds = List.of(_pinnedIds);
      _status = next.failedSources.isNotEmpty
          ? LibraryStatus.partial
          : _isEmpty(next)
          ? LibraryStatus.empty
          : LibraryStatus.ready;
    } on LibraryLoadFailure catch (error) {
      if (!_isCurrentLoad(revision)) return;
      _overview = null;
      _errorMessage = error.message;
      _status = error.isOffline ? LibraryStatus.offline : LibraryStatus.error;
    } catch (error) {
      if (!_isCurrentLoad(revision)) return;
      _overview = null;
      _errorMessage = error.toString();
      _status = LibraryStatus.error;
    }
    _notify();
  }

  Future<void> retry() => load();

  void setIndexQuery(String value) => _setQuery(
    value,
    current: _indexQuery,
    assign: (next) => _indexQuery = next,
  );

  void setAllQuery(String value) =>
      _setQuery(value, current: _allQuery, assign: (next) => _allQuery = next);

  void clearIndexQuery() => setIndexQuery('');
  void clearAllQuery() => setAllQuery('');

  Future<bool> replacePinned(Iterable<String> ids) async {
    if (_disposed) return false;
    final next = _sanitizePinned(ids);
    final revision = ++_pinSaveRevision;
    _pinnedIds = next;
    _pinSaveError = null;
    _pendingPinSaves++;
    _notify();

    final operation = _pinSaveTail.then((_) => pinnedStore.save(List.of(next)));
    _pinSaveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );

    try {
      await operation;
      if (!_disposed) _confirmedPinnedIds = List.of(next);
      return true;
    } catch (error) {
      if (!_disposed && revision == _pinSaveRevision) {
        _pinnedIds = List.of(_confirmedPinnedIds);
        _pinSaveError = '保存失败，已恢复原配置：$error';
      }
      return false;
    } finally {
      if (!_disposed) {
        _pendingPinSaves--;
        _notify();
      }
    }
  }

  Future<bool> movePinned(int oldIndex, int newIndex) {
    final next = List<String>.of(_pinnedIds);
    if (oldIndex < 0 ||
        oldIndex >= next.length ||
        newIndex < 0 ||
        newIndex >= next.length) {
      return Future.value(false);
    }
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    return replacePinned(next);
  }

  Future<bool> removePinned(String id) =>
      replacePinned(_pinnedIds.where((candidate) => candidate != id));

  Future<bool> addPinned(String id) {
    if (_pinnedIds.contains(id)) return Future.value(true);
    if (!containers.any((container) => container.id == id)) {
      return Future.value(false);
    }
    if (!canPinMore) {
      _pinSaveError = '最多常驻 6 个容器，请先移除一个';
      _notify();
      return Future.value(false);
    }
    return replacePinned([..._pinnedIds, id]);
  }

  void _setQuery(
    String value, {
    required String current,
    required ValueChanged<String> assign,
  }) {
    if (_disposed || current == value) return;
    assign(value);
    _notify();
  }

  List<LibraryContainerSummary> _filter(
    List<LibraryContainerSummary> source,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return source;
    return [
      for (final container in source)
        if (container.label.toLowerCase().contains(needle) ||
            container.id.toLowerCase().contains(needle))
          container,
    ];
  }

  List<String> _sanitizePinned(Iterable<String> ids) {
    final available = containers.map((container) => container.id).toSet();
    final seen = <String>{};
    return [
      for (final id in ids)
        if (available.contains(id) && seen.add(id)) id,
    ].take(6).toList(growable: false);
  }

  bool _isEmpty(LibraryOverview value) =>
      value.customContainers.isEmpty &&
      value.recentAssets.isEmpty &&
      value.systemContainers.every((container) => container.totalCount == 0);

  bool _isCurrentLoad(int revision) => !_disposed && revision == _loadRevision;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadRevision++;
    _pinSaveRevision++;
    super.dispose();
  }
}
