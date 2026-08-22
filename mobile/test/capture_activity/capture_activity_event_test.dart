import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server voice activity is normalized as an App capture', () {
    final event = CaptureActivityEvent.fromServerPayload({
      'status': 'understanding',
      'source': 'voice',
      'client_task_id': 'voice-42',
    });

    expect(event, isNotNull);
    expect(event!.source, CaptureActivitySource.app);
    expect(event.aliases, contains('client:voice-42'));
    expect(event.source.label, 'REKA App');
  });
}
