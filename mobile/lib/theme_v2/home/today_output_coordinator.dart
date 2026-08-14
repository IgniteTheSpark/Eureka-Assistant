import 'package:flutter/material.dart';

enum TodayOutputKind { signal, asset }

@immutable
class TodayOutputItem {
  const TodayOutputItem({
    required this.kind,
    required this.id,
    required this.source,
    required this.reduceMotion,
  });

  final TodayOutputKind kind;
  final String id;
  final Offset source;
  final bool reduceMotion;
}

class TodayOutputCoordinator extends ChangeNotifier {
  final Set<String> _knownAssets = {};
  final Set<String> _knownSignals = {};
  final List<TodayOutputItem> _queue = [];
  Set<String> _currentAssets = {};
  Set<String> _currentSignals = {};
  TodayOutputItem? _producing;
  bool _initialized = false;

  TodayOutputItem? get producing => _producing;
  List<String> get queuedIds =>
      List.unmodifiable(_queue.map((item) => item.id));

  void reconcile({
    required Iterable<String> assetIds,
    required Iterable<String> signalIds,
    required Offset rekaCenter,
    bool suppressProduction = false,
    bool capacityAvailable = true,
    bool reduceMotion = false,
  }) {
    _currentAssets = assetIds.toSet();
    _currentSignals = signalIds.toSet();
    _knownAssets.retainAll(_currentAssets);
    _knownSignals.retainAll(_currentSignals);
    _queue.removeWhere((item) => !_isCurrent(item));
    if (_producing case final item? when !_isCurrent(item)) {
      _producing = null;
    }

    if (!_initialized) {
      _initialized = true;
      _knownAssets.addAll(_currentAssets);
      _knownSignals.addAll(_currentSignals);
      notifyListeners();
      return;
    }

    final pendingAssets = <String>{
      for (final item in _queue)
        if (item.kind == TodayOutputKind.asset) item.id,
      if (_producing?.kind == TodayOutputKind.asset) _producing!.id,
    };
    final pendingSignals = <String>{
      for (final item in _queue)
        if (item.kind == TodayOutputKind.signal) item.id,
      if (_producing?.kind == TodayOutputKind.signal) _producing!.id,
    };
    final newSignals = _currentSignals
        .difference(_knownSignals)
        .difference(pendingSignals);
    final newAssets = _currentAssets
        .difference(_knownAssets)
        .difference(pendingAssets);

    if (suppressProduction || !capacityAvailable) {
      _knownSignals.addAll(newSignals);
      _knownAssets.addAll(newAssets);
    } else {
      for (final id in signalIds) {
        if (!newSignals.contains(id)) continue;
        _queue.add(
          TodayOutputItem(
            kind: TodayOutputKind.signal,
            id: id,
            source: rekaCenter,
            reduceMotion: reduceMotion,
          ),
        );
      }
      for (final id in assetIds) {
        if (!newAssets.contains(id)) continue;
        _queue.add(
          TodayOutputItem(
            kind: TodayOutputKind.asset,
            id: id,
            source: rekaCenter,
            reduceMotion: reduceMotion,
          ),
        );
      }
    }
    _startNext();
    notifyListeners();
  }

  List<String> stableAssetIds(Iterable<String> all) => [
    for (final id in all)
      if (_knownAssets.contains(id) && !_isOwned(TodayOutputKind.asset, id)) id,
  ];

  List<String> stableSignalIds(Iterable<String> all) => [
    for (final id in all)
      if (_knownSignals.contains(id) && !_isOwned(TodayOutputKind.signal, id))
        id,
  ];

  void completeCurrent() {
    final item = _producing;
    if (item == null) return;
    if (_isCurrent(item)) {
      (item.kind == TodayOutputKind.asset ? _knownAssets : _knownSignals).add(
        item.id,
      );
    }
    _producing = null;
    _startNext();
    notifyListeners();
  }

  void cancelAll() {
    final items = <TodayOutputItem>[?_producing, ..._queue];
    for (final item in items) {
      if (!_isCurrent(item)) continue;
      (item.kind == TodayOutputKind.asset ? _knownAssets : _knownSignals).add(
        item.id,
      );
    }
    _producing = null;
    _queue.clear();
    notifyListeners();
  }

  bool _isCurrent(TodayOutputItem item) =>
      (item.kind == TodayOutputKind.asset ? _currentAssets : _currentSignals)
          .contains(item.id);

  bool _isOwned(TodayOutputKind kind, String id) =>
      (_producing?.kind == kind && _producing?.id == id) ||
      _queue.any((item) => item.kind == kind && item.id == id);

  void _startNext() {
    while (_producing == null && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (_isCurrent(next)) _producing = next;
    }
  }
}
