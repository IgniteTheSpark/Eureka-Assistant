import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';
import '../../pet/reka_nudges.dart';
import 'reka_inbox_item.dart';

enum RekaInboxStatus { idle, loading, refreshing, ready, partial, empty, error }

abstract interface class RekaInboxRepository {
  Future<List<Map<String, dynamic>>> loadPending();
  Future<List<Map<String, dynamic>>> loadRecent();
  Future<List<Map<String, dynamic>>> loadOffers();
  Future<void> outcome(String id, String status);
}

class ApiRekaInboxRepository implements RekaInboxRepository {
  ApiRekaInboxRepository([ApiClient? api])
    : _api = api ?? ApiClient(),
      _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<List<Map<String, dynamic>>> loadPending() =>
      _load('/api/nudges/pending');

  @override
  Future<List<Map<String, dynamic>>> loadRecent() => _load('/api/nudges');

  @override
  Future<List<Map<String, dynamic>>> loadOffers() => _load('/api/offers/today');

  Future<List<Map<String, dynamic>>> _load(String path) async {
    final response = await _api.getJson(path);
    final list =
        (response is Map ? response['nudges'] : null) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList(growable: false);
  }

  @override
  Future<void> outcome(String id, String status) async {
    final saved = await RekaNudges.instance.outcome(id, status, api: _api);
    if (!saved) throw StateError('REKA 状态同步失败');
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
}

class RekaInboxController extends ChangeNotifier {
  RekaInboxController({
    RekaInboxRepository? repository,
    bool? observeNudgeStore,
  }) : repository = repository ?? ApiRekaInboxRepository(),
       _ownsRepository = repository == null,
       _observesNudgeStore = observeNudgeStore ?? repository == null {
    if (_observesNudgeStore) {
      _seenBobSignal = RekaNudges.instance.bobSignal;
      _seenOutcomeSignal = RekaNudges.instance.outcomeSignal;
      RekaNudges.instance.addListener(_syncSharedOutcome);
    }
  }

  final RekaInboxRepository repository;
  final bool _ownsRepository;
  final bool _observesNudgeStore;

  RekaInboxStatus _status = RekaInboxStatus.idle;
  List<RekaInboxItem> _items = const [];
  String? _errorMessage;
  String? _mutationError;
  int _loadRevision = 0;
  bool _disposed = false;
  Future<void> _mutationTail = Future<void>.value();
  final Map<String, String> _confirmedStatuses = {};
  final Map<String, String> _sharedStatuses = {};
  final Map<String, int> _mutationRevisions = {};
  int _seenBobSignal = 0;
  int _seenOutcomeSignal = 0;

  RekaInboxStatus get status => _status;
  List<RekaInboxItem> get items => _items;
  String? get errorMessage => _errorMessage;
  String? get mutationError => _mutationError;
  int get unreadCount => _items.where((item) => item.isUnread).length;
  bool get isLoading => _status == RekaInboxStatus.loading;
  bool get isRefreshing => _status == RekaInboxStatus.refreshing;

  RekaInboxItem? itemById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> load({bool includeOffers = true}) async {
    if (_disposed) return;
    final revision = ++_loadRevision;
    _status = _items.isEmpty
        ? RekaInboxStatus.loading
        : RekaInboxStatus.refreshing;
    _errorMessage = null;
    _notify();

    await _mutationTail;
    if (!_isCurrentLoad(revision)) return;

    final results = <_InboxSourceResult>[];
    if (includeOffers) {
      // /offers/today may revive a prior-day dismissed offer. Let that
      // transaction land before reading history, otherwise a concurrent recent
      // snapshot can carry the stale terminal status and hide today's offer.
      results.addAll(
        await Future.wait([
          _capture(RekaInboxSource.pending, repository.loadPending),
          _capture(RekaInboxSource.offer, repository.loadOffers),
        ]),
      );
      if (!_isCurrentLoad(revision)) return;
      results.add(
        await _capture(RekaInboxSource.recent, repository.loadRecent),
      );
    } else {
      results.addAll(
        await Future.wait([
          _capture(RekaInboxSource.pending, repository.loadPending),
          _capture(RekaInboxSource.recent, repository.loadRecent),
        ]),
      );
    }
    if (!_isCurrentLoad(revision)) return;

    final successes = results.where((result) => result.error == null).toList();
    final failures = results.where((result) => result.error != null).toList();
    if (successes.isEmpty) {
      _status = RekaInboxStatus.error;
      _errorMessage = 'Inbox 暂时无法加载，请重试';
      _notify();
      return;
    }

    final merged = <String, RekaInboxItem>{};
    for (final result in successes) {
      for (final row in result.rows) {
        try {
          final item = RekaInboxItem.fromJson(row, source: result.source);
          merged.update(
            item.id,
            (current) => current.mergedWith(item),
            ifAbsent: () => item,
          );
        } on FormatException {
          // One malformed row must not hide the rest of the inbox.
        }
      }
    }
    final items =
        merged.values
            .map(
              (item) => switch (_sharedStatuses[item.id]) {
                final status? => item.copyWith(status: status),
                null => item,
              },
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _items = List.unmodifiable(items);
    _confirmedStatuses
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item.status)));
    _mutationError = null;
    if (failures.isNotEmpty) {
      _status = RekaInboxStatus.partial;
      _errorMessage = '部分 REKA 信号加载失败，可重试刷新';
    } else if (items.isEmpty) {
      _status = RekaInboxStatus.empty;
      _errorMessage = null;
    } else {
      _status = RekaInboxStatus.ready;
      _errorMessage = null;
    }
    _notify();
  }

  Future<void> retry() => load();

  Future<bool> markSeen(String id) => _setOutcome(id, 'seen');
  Future<bool> markActed(String id) => _setOutcome(id, 'acted');
  Future<bool> markDismissed(String id) => _setOutcome(id, 'dismissed');

  Future<bool> markAllSeen() async {
    var success = true;
    final unreadIds = [
      for (final item in _items)
        if (item.isUnread) item.id,
    ];
    for (final id in unreadIds) {
      success = await markSeen(id) && success;
    }
    return success;
  }

  void _syncSharedOutcome() {
    if (_disposed) return;
    final store = RekaNudges.instance;
    if (_seenBobSignal != store.bobSignal) {
      _seenBobSignal = store.bobSignal;
      unawaited(load(includeOffers: false));
    }
    if (_seenOutcomeSignal == store.outcomeSignal) return;
    _seenOutcomeSignal = store.outcomeSignal;
    final outcome = store.latestOutcome;
    if (outcome == null) {
      _items = const [];
      _confirmedStatuses.clear();
      _sharedStatuses.clear();
      _status = RekaInboxStatus.empty;
      _notify();
      return;
    }
    _sharedStatuses[outcome.id] = outcome.status;
    if (itemById(outcome.id) == null) return;
    _replaceStatus(outcome.id, outcome.status);
    if (outcome.committed) {
      _confirmedStatuses[outcome.id] = outcome.status;
    }
    _notify();
  }

  Future<bool> _setOutcome(String id, String status) async {
    if (_disposed) return false;
    final item = itemById(id);
    if (item == null || item.status == status) return item != null;
    final revision = (_mutationRevisions[id] ?? 0) + 1;
    _mutationRevisions[id] = revision;
    _replaceStatus(id, status);
    _mutationError = null;
    _notify();

    final mutation = _mutationTail.then((_) async {
      await repository.outcome(id, status);
      _confirmedStatuses[id] = status;
    });
    _mutationTail = mutation.then<void>((_) {}, onError: (_, _) {});
    try {
      await mutation;
      return true;
    } catch (error) {
      if (!_disposed && revision == _mutationRevisions[id]) {
        _replaceStatus(id, _confirmedStatuses[id] ?? item.status);
        _mutationError = '状态更新失败，已恢复：$error';
        _notify();
      }
      return false;
    }
  }

  void _replaceStatus(String id, String status) {
    _items = List.unmodifiable([
      for (final item in _items)
        if (item.id == id) item.copyWith(status: status) else item,
    ]);
  }

  Future<_InboxSourceResult> _capture(
    RekaInboxSource source,
    Future<List<Map<String, dynamic>>> Function() load,
  ) async {
    try {
      return _InboxSourceResult(source, await load());
    } catch (error) {
      return _InboxSourceResult(source, const [], error);
    }
  }

  bool _isCurrentLoad(int revision) => !_disposed && revision == _loadRevision;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadRevision++;
    _mutationRevisions.clear();
    if (_observesNudgeStore) {
      RekaNudges.instance.removeListener(_syncSharedOutcome);
    }
    if (_ownsRepository && repository is ApiRekaInboxRepository) {
      (repository as ApiRekaInboxRepository).dispose();
    }
    super.dispose();
  }
}

class _InboxSourceResult {
  const _InboxSourceResult(this.source, this.rows, [this.error]);

  final RekaInboxSource source;
  final List<Map<String, dynamic>> rows;
  final Object? error;
}
