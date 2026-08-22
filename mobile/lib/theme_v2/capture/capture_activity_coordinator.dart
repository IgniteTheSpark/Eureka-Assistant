import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../capture_activity/capture_activity_bus.dart';
import '../../capture_activity/capture_activity_event.dart';
import 'capture_activity_models.dart';

typedef CaptureActivitySchedule =
    void Function(Duration duration, VoidCallback callback);

class CaptureActivityCoordinator extends ChangeNotifier {
  CaptureActivityCoordinator({
    CaptureActivityBus? bus,
    CaptureActivitySchedule? schedule,
  }) : _schedule = schedule ?? _defaultSchedule {
    _subscription = bus?.stream.listen(apply);
  }

  static final CaptureActivityCoordinator instance = CaptureActivityCoordinator(
    bus: CaptureActivityBus.instance,
  );

  final CaptureActivitySchedule _schedule;
  final Map<int, _CaptureTask> _tasks = {};
  final Set<int> _scheduledTerminalTasks = {};
  StreamSubscription<CaptureActivityEvent>? _subscription;
  int _nextKey = 0;
  int? _activeKey;
  bool _disposed = false;
  CaptureActivitySnapshot _snapshot = const CaptureActivitySnapshot();

  CaptureActivitySnapshot get snapshot => _snapshot;

  static void _defaultSchedule(Duration duration, VoidCallback callback) {
    Future<void>.delayed(duration, callback);
  }

  void apply(CaptureActivityEvent event) {
    if (_disposed || event.aliases.isEmpty) return;
    final matches = _tasks.values
        .where((task) => task.aliases.intersection(event.aliases).isNotEmpty)
        .toList();
    late _CaptureTask task;
    if (matches.isEmpty) {
      task = _CaptureTask.fromEvent(++_nextKey, event);
      _tasks[task.key] = task;
    } else {
      task = matches.first;
      for (final duplicate in matches.skip(1)) {
        task.mergeTask(duplicate);
        _tasks.remove(duplicate.key);
        if (_activeKey == duplicate.key) _activeKey = task.key;
      }
      task.apply(event);
    }

    _selectActive();
    if (task.phase.isTerminal && _scheduledTerminalTasks.add(task.key)) {
      _schedule(_terminalDwell(task.phase), () => _removeTerminal(task.key));
    }
    _emitSnapshot();
  }

  void applyAll(Iterable<CaptureActivityEvent> events) {
    for (final event in events) {
      apply(event);
    }
  }

  void _selectActive() {
    final current = _activeKey == null ? null : _tasks[_activeKey];
    if (current == null) {
      _activeKey = _bestCandidate()?.key;
      return;
    }
    if (!current.isRealtime && !current.phase.isTerminal) {
      final live = _oldest(
        _tasks.values.where(
          (task) => task.isRealtime && !task.phase.isTerminal,
        ),
      );
      if (live != null) _activeKey = live.key;
    }
  }

  _CaptureTask? _bestCandidate() {
    return _oldest(
          _tasks.values.where(
            (task) => task.isRealtime && !task.phase.isTerminal,
          ),
        ) ??
        _oldest(_tasks.values);
  }

  _CaptureTask? _oldest(Iterable<_CaptureTask> candidates) {
    final sorted = candidates.toList()
      ..sort((a, b) {
        final byTime = a.occurredAt.compareTo(b.occurredAt);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    return sorted.isEmpty ? null : sorted.first;
  }

  void _removeTerminal(int key) {
    if (_disposed) return;
    final task = _tasks[key];
    if (task == null || !task.phase.isTerminal) return;
    _tasks.remove(key);
    _scheduledTerminalTasks.remove(key);
    if (_activeKey == key) _activeKey = null;
    _selectActive();
    _emitSnapshot();
  }

  void _emitSnapshot() {
    final active = _activeKey == null ? null : _tasks[_activeKey];
    final activities = _tasks.values.toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    _snapshot = CaptureActivitySnapshot(
      active: active?.toItem(),
      queuedCount: active == null ? 0 : _tasks.length - 1,
      activities: List.unmodifiable(
        activities.map((activity) => activity.toItem()),
      ),
    );
    notifyListeners();
  }

  Duration _terminalDwell(CaptureActivityPhase phase) => switch (phase) {
    CaptureActivityPhase.done => const Duration(seconds: 2),
    CaptureActivityPhase.empty => const Duration(seconds: 3),
    CaptureActivityPhase.failed => const Duration(seconds: 4),
    _ => Duration.zero,
  };

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

class _CaptureTask {
  _CaptureTask.fromEvent(this.key, CaptureActivityEvent event)
    : aliases = {...event.aliases},
      source = event.source,
      phase = event.phase,
      isRealtime = event.isRealtime,
      occurredAt = event.occurredAt,
      phaseStartedAt = event.occurredAt,
      sessionId = event.sessionId,
      inputTurnId = event.inputTurnId,
      resultCount = event.resultCount;

  final int key;
  final Set<String> aliases;
  CaptureActivitySource source;
  CaptureActivityPhase phase;
  bool isRealtime;
  DateTime occurredAt;
  DateTime phaseStartedAt;
  String? sessionId;
  String? inputTurnId;
  int? resultCount;

  void apply(CaptureActivityEvent event) {
    aliases.addAll(event.aliases);
    isRealtime = isRealtime || event.isRealtime;
    if (event.occurredAt.isBefore(occurredAt)) occurredAt = event.occurredAt;
    sessionId = event.sessionId ?? sessionId;
    inputTurnId = event.inputTurnId ?? inputTurnId;
    resultCount = event.resultCount ?? resultCount;
    if (!phase.isTerminal &&
        (event.phase.isTerminal || event.phase.index >= phase.index)) {
      if (event.phase != phase) {
        phase = event.phase;
        source = event.source;
        phaseStartedAt = event.occurredAt;
      }
    }
  }

  void mergeTask(_CaptureTask other) {
    aliases.addAll(other.aliases);
    isRealtime = isRealtime || other.isRealtime;
    if (other.occurredAt.isBefore(occurredAt)) occurredAt = other.occurredAt;
    sessionId ??= other.sessionId;
    inputTurnId ??= other.inputTurnId;
    resultCount ??= other.resultCount;
    if (!phase.isTerminal &&
        (other.phase.isTerminal || other.phase.index > phase.index)) {
      phase = other.phase;
      source = other.source;
      phaseStartedAt = other.phaseStartedAt;
    } else if (other.phase == phase &&
        other.phaseStartedAt.isBefore(phaseStartedAt)) {
      phaseStartedAt = other.phaseStartedAt;
    }
  }

  CaptureActivityItem toItem() => CaptureActivityItem(
    aliases: Set.unmodifiable(aliases),
    source: source,
    phase: phase,
    isRealtime: isRealtime,
    occurredAt: occurredAt,
    phaseStartedAt: phaseStartedAt,
    sessionId: sessionId,
    inputTurnId: inputTurnId,
    resultCount: resultCount,
  );
}
