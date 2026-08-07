import 'dart:async';

import 'capture_activity_event.dart';

class CaptureActivityBus {
  CaptureActivityBus();

  static final CaptureActivityBus instance = CaptureActivityBus();

  final StreamController<CaptureActivityEvent> _events =
      StreamController<CaptureActivityEvent>.broadcast(sync: true);

  Stream<CaptureActivityEvent> get stream => _events.stream;

  void publish(CaptureActivityEvent event) => _events.add(event);
}
