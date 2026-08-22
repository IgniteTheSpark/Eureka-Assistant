import 'package:flutter/foundation.dart';

import '../home/today_output_coordinator.dart';
import '../home/today_reka_capture_cue.dart';

@immutable
class ShellRekaPresentation {
  const ShellRekaPresentation({
    this.refreshSignal = 0,
    this.cue = const TodayOutputCue.idle(),
    this.captureCue = const TodayRekaCaptureCue.idle(),
  });

  final int refreshSignal;
  final TodayOutputCue cue;
  final TodayRekaCaptureCue captureCue;
}

class ShellRekaPresentationController extends ChangeNotifier {
  ShellRekaPresentation _value = const ShellRekaPresentation();

  ShellRekaPresentation get value => _value;

  void update({
    required int refreshSignal,
    required TodayOutputCue cue,
    required TodayRekaCaptureCue captureCue,
  }) {
    final current = _value;
    if (current.refreshSignal == refreshSignal &&
        _sameCue(current.cue, cue) &&
        current.captureCue == captureCue) {
      return;
    }
    _value = ShellRekaPresentation(
      refreshSignal: refreshSignal,
      cue: cue,
      captureCue: captureCue,
    );
    notifyListeners();
  }

  static bool _sameCue(TodayOutputCue left, TodayOutputCue right) =>
      left.phase == right.phase &&
      left.kind == right.kind &&
      left.id == right.id &&
      left.side == right.side &&
      left.source == right.source &&
      left.reduceMotion == right.reduceMotion;
}
