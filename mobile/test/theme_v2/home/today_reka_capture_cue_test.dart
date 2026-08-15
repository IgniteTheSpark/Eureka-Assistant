import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/theme_v2/capture/capture_activity_models.dart';
import 'package:eureka/theme_v2/home/today_reka_capture_cue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty capture snapshot maps to an idle Reka cue', () {
    expect(
      TodayRekaCaptureCue.fromSnapshot(const CaptureActivitySnapshot()),
      const TodayRekaCaptureCue.idle(),
    );
  });

  test('every capture phase keeps its distinct Reka action', () {
    for (final phase in CaptureActivityPhase.values) {
      final cue = TodayRekaCaptureCue.fromSnapshot(
        CaptureActivitySnapshot(
          active: CaptureActivityItem(
            aliases: const {'client:capture-1'},
            source: CaptureActivitySource.ring,
            phase: phase,
            isRealtime: true,
            occurredAt: DateTime.utc(2026, 8, 15),
          ),
        ),
      );

      expect(cue.action.name, phase.name);
      expect(cue.phase, phase);
      expect(cue.source, CaptureActivitySource.ring);
      expect(cue.isRealtime, isTrue);
      expect(cue.isActive, isTrue);
      expect(cue.toRendererPayload(), {
        'action': phase.name,
        'source': 'ring',
        'isRealtime': true,
      });
    }
  });
}
