import 'package:flutter/foundation.dart';

import '../../capture_activity/capture_activity_event.dart';
import '../capture/capture_activity_models.dart';

enum TodayRekaCaptureAction {
  idle,
  listening,
  receiving,
  transcribing,
  understanding,
  organizing,
  done,
  empty,
  failed,
}

@immutable
class TodayRekaCaptureCue {
  const TodayRekaCaptureCue({
    required this.action,
    this.phase,
    this.source,
    this.isRealtime = false,
  });

  const TodayRekaCaptureCue.idle()
    : action = TodayRekaCaptureAction.idle,
      phase = null,
      source = null,
      isRealtime = false;

  factory TodayRekaCaptureCue.fromSnapshot(CaptureActivitySnapshot snapshot) {
    final activity = snapshot.active;
    if (activity == null) return const TodayRekaCaptureCue.idle();
    return TodayRekaCaptureCue(
      action: TodayRekaCaptureAction.values.byName(activity.phase.name),
      phase: activity.phase,
      source: activity.source,
      isRealtime: activity.isRealtime,
    );
  }

  final TodayRekaCaptureAction action;
  final CaptureActivityPhase? phase;
  final CaptureActivitySource? source;
  final bool isRealtime;

  bool get isActive => action != TodayRekaCaptureAction.idle;

  Map<String, Object?> toRendererPayload() => {
    'action': action.name,
    'source': source?.name,
    'isRealtime': isRealtime,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodayRekaCaptureCue &&
          action == other.action &&
          phase == other.phase &&
          source == other.source &&
          isRealtime == other.isRealtime;

  @override
  int get hashCode => Object.hash(action, phase, source, isRealtime);
}
