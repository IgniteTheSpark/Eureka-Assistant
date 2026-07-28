import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api_client.dart';
import '../../assets/assets.dart';
import '../../timeline/timeline.dart';

enum LibraryStatus { idle, loading, ready, partial, empty, offline, error }

enum LibraryContainerKind { asset, event, contact, report, external }

@immutable
class LibraryContainer {
  const LibraryContainer({
    required this.id,
    required this.label,
    required this.icon,
    required this.kind,
    required this.count,
    required this.isSystem,
    this.userSkillId,
  });

  final String id;
  final String label;
  final String icon;
  final LibraryContainerKind kind;
  final int count;
  final bool isSystem;
  final String? userSkillId;
}

@immutable
class LibraryRecentItem {
  const LibraryRecentItem({
    required this.id,
    required this.containerId,
    required this.title,
    required this.effectiveAt,
    this.card = const {},
  });

  final String id;
  final String containerId;
  final String title;
  final DateTime effectiveAt;
  final Map<String, dynamic> card;
}

@immutable
class LibrarySnapshot {
  const LibrarySnapshot({
    this.assets = const [],
    this.skills = const {},
    this.events = const [],
    this.contacts = const [],
    this.reports = const [],
    this.assetCounts = const {},
    this.failedSources = const {},
    this.availableSources = const {},
  });

  final List<AssetItem> assets;
  final Map<String, SkillMeta> skills;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> contacts;
  final List<Map<String, dynamic>> reports;
  final Map<String, int> assetCounts;
  final Set<String> failedSources;
  final Set<String> availableSources;

  int get eventCount => events.length;
  int get contactCount => contacts.length;
  int get reportCount => reports.length;
  int get assetTotal => assetCounts.values.fold(0, (sum, count) => sum + count);

  List<LibraryContainer> get containers {
    final result = <LibraryContainer>[];
    for (final entry in skills.entries) {
      final key = entry.key;
      final meta = entry.value;
      if (!meta.enabled || key == 'qa' || key == 'contact') continue;
      result.add(
        LibraryContainer(
          id: key,
          label: meta.label,
          icon: meta.icon,
          kind: key == 'external_ref'
              ? LibraryContainerKind.external
              : LibraryContainerKind.asset,
          count: assetCounts[key] ?? 0,
          isSystem: _systemContainerIds.contains(key),
          userSkillId: meta.userSkillId,
        ),
      );
    }
    if (availableSources.contains('events')) {
      result.add(
        LibraryContainer(
          id: 'event',
          label: '事件',
          icon: '📅',
          kind: LibraryContainerKind.event,
          count: eventCount,
          isSystem: true,
        ),
      );
    }
    if (availableSources.contains('contacts')) {
      result.add(
        LibraryContainer(
          id: 'contact',
          label: '联系人',
          icon: '👤',
          kind: LibraryContainerKind.contact,
          count: contactCount,
          isSystem: true,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  int get containerCount => containers.length;
  int get customContainerCount =>
      containers.where((container) => !container.isSystem).length;
  int get activeSignalCount =>
      containers.where((container) => !container.isSystem).length;

  List<LibraryRecentItem> get recentItems {
    final result = <LibraryRecentItem>[
      for (final asset in assets)
        LibraryRecentItem(
          id: asset.id,
          containerId: asset.skillName,
          title: asset.title,
          effectiveAt: asset.effectiveAt,
          card: {
            'asset_id': asset.id,
            'user_skill_id':
                asset.userSkillId ?? skills[asset.skillName]?.userSkillId,
            'user_skill_name': asset.skillName,
            'payload': asset.payload,
            'session_id': asset.sessionId,
            'domain': asset.domain,
          },
        ),
      for (final event in events)
        LibraryRecentItem(
          id: _entityId(event),
          containerId: 'event',
          title: _entityTitle(event, const ['title', 'summary']),
          effectiveAt: _entityTime(event, const [
            'effective_at',
            'start_at',
            'occurred_at',
            'created_at',
          ]),
          card: {'card_type': 'event', ...event},
        ),
      for (final contact in contacts)
        LibraryRecentItem(
          id: _entityId(contact),
          containerId: 'contact',
          title: _entityTitle(contact, const [
            'name',
            'display_name',
            'company',
          ]),
          effectiveAt: _entityTime(contact),
          card: {'card_type': 'contact', ...contact},
        ),
      for (final report in reports)
        LibraryRecentItem(
          id: _entityId(report),
          containerId: 'report',
          title: _entityTitle(report, const ['title', 'name']),
          effectiveAt: _entityTime(report),
          card: {'card_type': 'report', ...report},
        ),
    ]..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
    return List.unmodifiable(result);
  }

  static String _entityId(Map<String, dynamic> entity) {
    for (final key in const [
      'id',
      'event_id',
      'contact_id',
      'report_id',
      'asset_id',
    ]) {
      final value = entity[key]?.toString() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _entityTitle(
    Map<String, dynamic> entity,
    List<String> candidates,
  ) {
    for (final key in candidates) {
      final value = entity[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '未命名';
  }

  static DateTime _entityTime(
    Map<String, dynamic> entity, [
    List<String> fields = const ['effective_at', 'created_at'],
  ]) {
    for (final field in fields) {
      final parsed = DateTime.tryParse(
        entity[field]?.toString() ?? '',
      )?.toLocal();
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

const _systemContainerIds = {'todo', 'notes', 'external_ref'};

abstract interface class LibraryRepository {
  Future<LibrarySnapshot> load();
}

class LibraryLoadFailure implements Exception {
  const LibraryLoadFailure(this.message, {this.isOffline = false});

  const LibraryLoadFailure.offline() : message = '网络不可用', isOffline = true;

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}

class ApiLibraryRepository implements LibraryRepository {
  ApiLibraryRepository(this.api);

  final ApiClient api;

  @override
  Future<LibrarySnapshot> load() async {
    final values = await Future.wait<Object?>([
      _capture('assets', () => fetchAssets(api)),
      _capture('skills', () => fetchSkills(api)),
      _capture('events', () => _fetchList('/api/events', 'events')),
      _capture('contacts', () => _fetchList('/api/contacts', 'contacts')),
      _capture('reports', () => _fetchList('/api/reports', 'reports')),
      _capture('counts', _fetchCounts),
    ]);
    final failures = values.whereType<_SourceFailure>().toList();
    if (failures.length == values.length) {
      throw LibraryLoadFailure(
        '资产库暂时无法加载',
        isOffline: failures.any((failure) => failure.isOffline),
      );
    }

    final failedSources = failures.map((failure) => failure.source).toSet();
    final assets = _value<List<AssetItem>>(values[0]) ?? const [];
    final counts =
        _value<Map<String, int>>(values[5]) ?? _countsFromAssets(assets);
    return LibrarySnapshot(
      assets: assets,
      skills: _value<Map<String, SkillMeta>>(values[1]) ?? const {},
      events: _value<List<Map<String, dynamic>>>(values[2]) ?? const [],
      contacts: _value<List<Map<String, dynamic>>>(values[3]) ?? const [],
      reports: _value<List<Map<String, dynamic>>>(values[4]) ?? const [],
      assetCounts: counts,
      failedSources: failedSources,
      availableSources: {
        for (final source in const {
          'assets',
          'skills',
          'events',
          'contacts',
          'reports',
          'counts',
        })
          if (!failedSources.contains(source)) source,
      },
    );
  }

  Future<Object?> _capture(
    String source,
    Future<Object?> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (error) {
      return _SourceFailure(source, _isOfflineError(error));
    }
  }

  T? _value<T>(Object? value) => value is T ? value : null;

  Future<List<Map<String, dynamic>>> _fetchList(String path, String key) async {
    final response = await api.getJson(path);
    final list = (response is Map ? response[key] : null) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, int>> _fetchCounts() async {
    final response = await api.getJson('/api/assets/counts');
    final counts =
        (response is Map ? response['counts'] : null) as Map? ?? const {};
    return counts.map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    );
  }

  Map<String, int> _countsFromAssets(List<AssetItem> assets) {
    final result = <String, int>{};
    for (final asset in assets) {
      result.update(asset.skillName, (count) => count + 1, ifAbsent: () => 1);
    }
    return result;
  }

  bool _isOfflineError(Object error) =>
      error is SocketException ||
      error is http.ClientException ||
      (error is ApiException && error.statusCode == 503);
}

class _SourceFailure {
  const _SourceFailure(this.source, this.isOffline);

  final String source;
  final bool isOffline;
}

abstract interface class LibraryPinnedStore {
  Future<List<String>?> load();
  Future<void> save(List<String> ids);
}

class SharedPreferencesLibraryPinnedStore implements LibraryPinnedStore {
  const SharedPreferencesLibraryPinnedStore();

  static const _key = 'theme_v2.library.pinned_order';

  @override
  Future<List<String>?> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_key);
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
  LibrarySnapshot? _snapshot;
  List<String> _pinnedIds = const [];
  String _query = '';
  String? _errorMessage;
  String? _pinSaveError;
  List<String> _confirmedPinnedIds = const [];
  Future<void> _pinSaveTail = Future<void>.value();
  int _pinSaveRevision = 0;
  int _loadRevision = 0;
  bool _disposed = false;

  LibraryStatus get status => _status;
  LibrarySnapshot? get snapshot => _snapshot;
  String? get errorMessage => _errorMessage;
  String? get pinSaveError => _pinSaveError;
  String get query => _query;
  bool get isLoading => _status == LibraryStatus.loading;

  String? get statusMessage {
    if (_status == LibraryStatus.partial) {
      return '部分内容加载失败，可重试刷新';
    }
    return null;
  }

  List<LibraryContainer> get containers => _snapshot?.containers ?? const [];

  List<LibraryContainer> get filteredContainers {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return containers;
    return containers
        .where(
          (container) =>
              container.label.toLowerCase().contains(needle) ||
              container.id.toLowerCase().contains(needle),
        )
        .toList(growable: false);
  }

  List<LibraryContainer> get systemContainers => filteredContainers
      .where((container) => container.isSystem)
      .toList(growable: false);

  List<LibraryContainer> get customContainers => filteredContainers
      .where((container) => !container.isSystem)
      .toList(growable: false);

  List<LibraryContainer> get pinnedContainers {
    final byId = {for (final container in containers) container.id: container};
    return [for (final id in _pinnedIds) ?byId[id]];
  }

  List<LibraryContainer> get availableToPin {
    final selected = _pinnedIds.toSet();
    return containers
        .where((container) => !selected.contains(container.id))
        .toList(growable: false);
  }

  bool get canPinMore => _pinnedIds.length < 6;

  Future<void> load() async {
    if (_disposed) return;
    final revision = ++_loadRevision;
    _status = LibraryStatus.loading;
    _errorMessage = null;
    _notifyListeners();
    try {
      final snapshot = await repository.load();
      if (!_isCurrentLoad(revision)) return;
      await _pinSaveTail;
      if (!_isCurrentLoad(revision)) return;
      List<String>? persisted;
      try {
        persisted = await pinnedStore.load();
      } catch (error) {
        persisted = null;
        _pinSaveError = '无法读取常驻配置：$error';
      }
      if (!_isCurrentLoad(revision)) return;
      _snapshot = snapshot;
      final defaults = snapshot.containers.map((item) => item.id);
      _pinnedIds = persisted == null
          ? _sanitizePinned(defaults)
          : _sanitizePinned(persisted);
      _confirmedPinnedIds = List<String>.of(_pinnedIds);
      _status = snapshot.failedSources.isNotEmpty
          ? LibraryStatus.partial
          : snapshot.containers.isEmpty
          ? LibraryStatus.empty
          : LibraryStatus.ready;
    } on LibraryLoadFailure catch (error) {
      if (revision != _loadRevision) return;
      _snapshot = null;
      _errorMessage = error.message;
      _status = error.isOffline ? LibraryStatus.offline : LibraryStatus.error;
    } catch (error) {
      if (revision != _loadRevision) return;
      _snapshot = null;
      _errorMessage = error.toString();
      _status = LibraryStatus.error;
    }
    _notifyListeners();
  }

  Future<void> retry() => load();

  void setQuery(String value) {
    if (_disposed || _query == value) return;
    _query = value;
    _notifyListeners();
  }

  Future<bool> replacePinned(Iterable<String> ids) async {
    if (_disposed) return false;
    final next = _sanitizePinned(ids);
    final revision = ++_pinSaveRevision;
    _pinnedIds = next;
    _pinSaveError = null;
    _notifyListeners();
    final save = _pinSaveTail.then((_) async {
      await pinnedStore.save(List<String>.of(next));
      _confirmedPinnedIds = List<String>.of(next);
    });
    _pinSaveTail = save.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await save;
      return true;
    } catch (error) {
      if (!_disposed && revision == _pinSaveRevision) {
        _pinnedIds = List<String>.of(_confirmedPinnedIds);
        _pinSaveError = '保存失败，已恢复原配置：$error';
        _notifyListeners();
      }
      return false;
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
    if (!canPinMore) {
      _pinSaveError = '最多常驻 6 个容器，请先移除一个';
      _notifyListeners();
      return Future.value(false);
    }
    return replacePinned([..._pinnedIds, id]);
  }

  List<String> _sanitizePinned(Iterable<String> ids) {
    final available = containers.map((container) => container.id).toSet();
    final seen = <String>{};
    return [
      for (final id in ids)
        if (available.contains(id) && seen.add(id)) id,
    ].take(6).toList();
  }

  bool _isCurrentLoad(int revision) => !_disposed && revision == _loadRevision;

  void _notifyListeners() {
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
