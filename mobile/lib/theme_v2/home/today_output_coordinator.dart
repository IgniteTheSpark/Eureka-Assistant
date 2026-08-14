import 'package:flutter/material.dart';

enum TodayOutputKind { signal, asset }

enum TodayOutputPhase { idle, charge, emit, handoff, recover }

enum TodayOutputSide { left, right }

@immutable
class TodayOutputCue {
  const TodayOutputCue({
    required this.phase,
    this.kind,
    this.id,
    this.side = TodayOutputSide.right,
    this.source = Offset.zero,
    this.reduceMotion = false,
  });

  const TodayOutputCue.idle()
    : phase = TodayOutputPhase.idle,
      kind = null,
      id = null,
      side = TodayOutputSide.right,
      source = Offset.zero,
      reduceMotion = false;

  final TodayOutputPhase phase;
  final TodayOutputKind? kind;
  final String? id;
  final TodayOutputSide side;
  final Offset source;
  final bool reduceMotion;
}

@immutable
class TodayOutputItem {
  const TodayOutputItem({
    required this.kind,
    required this.id,
    required this.source,
    required this.reduceMotion,
    this.side = TodayOutputSide.right,
  });

  final TodayOutputKind kind;
  final String id;
  final Offset source;
  final bool reduceMotion;
  final TodayOutputSide side;
}

class TodayOutputCoordinator extends ChangeNotifier {
  final Set<String> _knownAssets = {};
  final Set<String> _knownSignals = {};
  final List<TodayOutputItem> _queue = [];
  Set<String> _currentAssets = {};
  Set<String> _currentSignals = {};
  TodayOutputItem? _producing;
  TodayOutputPhase _phase = TodayOutputPhase.idle;
  bool _initialized = false;
  String? _lastCompletedSignalId;

  TodayOutputItem? get producing => _producing;
  String? get lastCompletedSignalId => _lastCompletedSignalId;
  TodayOutputCue get cue {
    final item = _producing;
    if (item == null) return const TodayOutputCue.idle();
    return TodayOutputCue(
      phase: _phase,
      kind: item.kind,
      id: item.id,
      side: item.side,
      source: item.source,
      reduceMotion: item.reduceMotion,
    );
  }

  List<String> get queuedIds =>
      List.unmodifiable(_queue.map((item) => item.id));

  void reconcile({
    required Iterable<String> assetIds,
    required Iterable<String> signalIds,
    required Offset rekaCenter,
    bool suppressProduction = false,
    bool capacityAvailable = true,
    bool reduceMotion = false,
    double viewportWidth = 411,
    double rekaRenderExtent = 288,
  }) {
    final before = _stateSignature();
    _currentAssets = assetIds.toSet();
    _currentSignals = signalIds.toSet();
    _knownAssets.retainAll(_currentAssets);
    _knownSignals.retainAll(_currentSignals);
    _queue.removeWhere((item) => !_isCurrent(item));
    if (_producing case final item? when !_isCurrent(item)) {
      _producing = null;
      _phase = TodayOutputPhase.idle;
    }

    if (!_initialized) {
      _initialized = true;
      _knownAssets.addAll(_currentAssets);
      _knownSignals.addAll(_currentSignals);
      _notifyIfChanged(before);
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
            side: _sideFor(
              rekaCenter,
              viewportWidth: viewportWidth,
              rekaRenderExtent: rekaRenderExtent,
            ),
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
            side: _sideFor(
              rekaCenter,
              viewportWidth: viewportWidth,
              rekaRenderExtent: rekaRenderExtent,
            ),
          ),
        );
      }
    }
    _startNext();
    _notifyIfChanged(before);
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
    if (item.kind == TodayOutputKind.signal) {
      _lastCompletedSignalId = item.id;
    }
    _producing = null;
    _phase = TodayOutputPhase.idle;
    _startNext();
    notifyListeners();
  }

  void updatePhase(TodayOutputPhase phase) {
    if (_producing == null ||
        phase == TodayOutputPhase.idle ||
        _phase == phase) {
      return;
    }
    _phase = phase;
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
    _phase = TodayOutputPhase.idle;
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
      if (_isCurrent(next)) {
        _producing = next;
        _phase = TodayOutputPhase.charge;
      }
    }
  }

  String _stateSignature() {
    final assets = _knownAssets.toList()..sort();
    final signals = _knownSignals.toList()..sort();
    return '${_producing?.kind.name}:${_producing?.id}:${_phase.name}|'
        '${_queue.map((item) => '${item.kind.name}:${item.id}').join(',')}|'
        '${assets.join(',')}|${signals.join(',')}|$_lastCompletedSignalId';
  }

  void _notifyIfChanged(String before) {
    if (_stateSignature() != before) notifyListeners();
  }

  TodayOutputSide _sideFor(
    Offset rekaCenter, {
    required double viewportWidth,
    required double rekaRenderExtent,
  }) {
    final rightEdge = rekaCenter.dx + rekaRenderExtent / 2 + 32;
    return rightEdge <= viewportWidth - 18
        ? TodayOutputSide.right
        : TodayOutputSide.left;
  }
}
