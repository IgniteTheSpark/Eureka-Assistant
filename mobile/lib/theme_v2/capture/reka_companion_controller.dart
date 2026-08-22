import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../capture_activity/capture_activity_event.dart';
import '../../voice_input/reka_voice_capture.dart';
import 'capture_activity_coordinator.dart';
import 'capture_activity_models.dart';
import 'reka_terminal_models.dart';

typedef RekaCompanionSchedule =
    void Function(Duration duration, VoidCallback callback);

class RekaCompanionController extends ChangeNotifier {
  RekaCompanionController({
    required RekaVoiceCaptureCoordinator voice,
    required CaptureActivityCoordinator activities,
    RekaCompanionSchedule? schedule,
  }) : _voice = voice,
       _activities = activities,
       _schedule = schedule ?? _defaultSchedule {
    _voice.addListener(_onSourceChanged);
    _activities.addListener(_onSourceChanged);
    _recompute();
  }

  final RekaVoiceCaptureCoordinator _voice;
  final CaptureActivityCoordinator _activities;
  final RekaCompanionSchedule _schedule;
  final Set<String> _dismissedAliases = <String>{};
  final Set<String> _handoffAliases = <String>{};

  RekaTerminalModel? _terminal;
  CaptureActivityItem? _openableActivity;
  int? _hiddenLocalEpoch;
  String? _scheduledLocalKey;
  int _scheduleGeneration = 0;
  bool _disposed = false;

  RekaTerminalModel? get terminal => _terminal;
  CaptureActivityItem? get openableActivity => _openableActivity;

  static void _defaultSchedule(Duration duration, VoidCallback callback) {
    Future<void>.delayed(duration, callback);
  }

  void _onSourceChanged() => _recompute();

  Future<void> dismissTerminal() async {
    final current = _terminal;
    if (current == null) return;
    _dismissedAliases.addAll(current.aliases);
    final local = current.aliases.contains('app-local:${_voice.captureEpoch}');
    if (local) {
      _hiddenLocalEpoch = _voice.captureEpoch;
      if (_isUnsubmittedRecording(_voice.state)) {
        await _voice.cancelGesture();
      }
    }
    _recompute();
  }

  bool _isUnsubmittedRecording(RekaVoiceCaptureState state) => switch (state) {
    RekaVoiceCaptureState.connecting ||
    RekaVoiceCaptureState.listening ||
    RekaVoiceCaptureState.cancelArmed ||
    RekaVoiceCaptureState.stopping => true,
    _ => false,
  };

  void _recompute() {
    if (_disposed) return;
    _cleanupDismissedAliases();
    _scheduleLocalTerminalIfNeeded();

    final localVisible =
        _voice.state != RekaVoiceCaptureState.idle &&
        _hiddenLocalEpoch != _voice.captureEpoch;
    RekaTerminalModel? next;
    CaptureActivityItem? openable;
    if (localVisible) {
      _handoffAliases
        ..clear()
        ..addAll(_localAliases());
      next = _modelFromVoice();
    } else {
      final visible = _activities.snapshot.activities
          .where((item) => !_isDismissed(item.aliases))
          .toList();
      final selected = _selectActivity(visible);
      if (selected != null) {
        next = _modelFromActivity(selected, visible.length - 1);
        if (selected.canOpenSession) openable = selected;
      }
    }

    _terminal = next;
    _openableActivity = openable;
    notifyListeners();
  }

  void _cleanupDismissedAliases() {
    final live = <String>{};
    if (_voice.state != RekaVoiceCaptureState.idle) {
      live.addAll(_localAliases());
    }
    for (final item in _activities.snapshot.activities) {
      live.addAll(item.aliases);
    }
    _dismissedAliases.removeWhere((alias) => !live.contains(alias));
  }

  bool _isDismissed(Set<String> aliases) =>
      aliases.any(_dismissedAliases.contains);

  CaptureActivityItem? _selectActivity(List<CaptureActivityItem> visible) {
    if (visible.isEmpty) return null;
    for (final item in visible) {
      if (item.aliases.intersection(_handoffAliases).isNotEmpty) return item;
    }
    final active = _activities.snapshot.active;
    if (active != null) {
      for (final item in visible) {
        if (item.aliases.intersection(active.aliases).isNotEmpty) return item;
      }
    }
    final realtime = visible
        .where((item) => item.isRealtime && !item.phase.isTerminal)
        .toList();
    final candidates = realtime.isEmpty ? visible : realtime;
    candidates.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return candidates.first;
  }

  Set<String> _localAliases() => <String>{
    'app-local:${_voice.captureEpoch}',
    if (_voice.voiceSessionId case final sessionId?) 'client:$sessionId',
  };

  RekaTerminalModel _modelFromVoice() {
    final aliases = _localAliases();
    final phase = switch (_voice.state) {
      RekaVoiceCaptureState.idle => throw StateError('idle has no terminal'),
      RekaVoiceCaptureState.connecting => RekaTerminalPhase.connecting,
      RekaVoiceCaptureState.listening => RekaTerminalPhase.listening,
      RekaVoiceCaptureState.cancelArmed => RekaTerminalPhase.cancelArmed,
      RekaVoiceCaptureState.stopping => RekaTerminalPhase.transcribing,
      RekaVoiceCaptureState.sending => RekaTerminalPhase.sending,
      RekaVoiceCaptureState.empty => RekaTerminalPhase.empty,
      RekaVoiceCaptureState.error => RekaTerminalPhase.failed,
    };
    final queuedCount = _activities.snapshot.activities
        .where((item) => item.aliases.intersection(aliases).isEmpty)
        .length;
    return RekaTerminalModel(
      identity: _identityForAliases(aliases),
      aliases: Set.unmodifiable(aliases),
      source: CaptureActivitySource.app,
      phase: phase,
      statusLabel: _localStatusLabel(phase),
      transcript: _voice.transcript,
      queuedCount: queuedCount,
    );
  }

  String _localStatusLabel(RekaTerminalPhase phase) => switch (phase) {
    RekaTerminalPhase.connecting => '正在连接语音',
    RekaTerminalPhase.listening => '聆听中',
    RekaTerminalPhase.cancelArmed => '松开取消',
    RekaTerminalPhase.transcribing => '正在完成转写',
    RekaTerminalPhase.sending => '正在发送闪念',
    RekaTerminalPhase.empty => '未识别到有效内容',
    RekaTerminalPhase.failed => '语音输入失败',
    _ => throw StateError('not a local phase: $phase'),
  };

  RekaTerminalModel _modelFromActivity(
    CaptureActivityItem item,
    int queuedCount,
  ) {
    final phase = switch (item.phase) {
      CaptureActivityPhase.listening => RekaTerminalPhase.listening,
      CaptureActivityPhase.receiving => RekaTerminalPhase.receiving,
      CaptureActivityPhase.transcribing => RekaTerminalPhase.transcribing,
      CaptureActivityPhase.understanding => RekaTerminalPhase.understanding,
      CaptureActivityPhase.organizing => RekaTerminalPhase.organizing,
      CaptureActivityPhase.done => RekaTerminalPhase.done,
      CaptureActivityPhase.empty => RekaTerminalPhase.empty,
      CaptureActivityPhase.failed => RekaTerminalPhase.failed,
    };
    return RekaTerminalModel(
      identity: _identityForAliases(item.aliases),
      aliases: item.aliases,
      source: item.source,
      phase: phase,
      statusLabel: item.statusLabel,
      resultCount: item.resultCount,
      queuedCount: queuedCount,
      canOpenDetail: item.canOpenSession,
    );
  }

  String _identityForAliases(Set<String> aliases) {
    for (final prefix in const ['client:', 'recording:', 'app-local:']) {
      for (final alias in aliases) {
        if (alias.startsWith(prefix)) return alias;
      }
    }
    final sorted = aliases.toList()..sort();
    return sorted.first;
  }

  void _scheduleLocalTerminalIfNeeded() {
    final duration = switch (_voice.state) {
      RekaVoiceCaptureState.empty => const Duration(seconds: 3),
      RekaVoiceCaptureState.error => const Duration(seconds: 4),
      _ => null,
    };
    if (duration == null) {
      _scheduledLocalKey = null;
      _scheduleGeneration += 1;
      return;
    }
    final key = '${_voice.captureEpoch}:${_voice.state.name}';
    if (_scheduledLocalKey == key) return;
    _scheduledLocalKey = key;
    final generation = ++_scheduleGeneration;
    final epoch = _voice.captureEpoch;
    _schedule(duration, () {
      if (_disposed ||
          generation != _scheduleGeneration ||
          epoch != _voice.captureEpoch) {
        return;
      }
      _hiddenLocalEpoch = epoch;
      _recompute();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduleGeneration += 1;
    _voice.removeListener(_onSourceChanged);
    _activities.removeListener(_onSourceChanged);
    super.dispose();
  }
}
