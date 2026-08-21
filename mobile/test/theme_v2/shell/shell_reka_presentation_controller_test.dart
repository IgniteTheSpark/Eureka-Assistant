import 'package:eureka/theme_v2/home/today_output_coordinator.dart';
import 'package:eureka/theme_v2/home/today_reka_capture_cue.dart';
import 'package:eureka/theme_v2/shell/shell_reka_presentation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation controller deduplicates identical renderer state', () {
    final controller = ShellRekaPresentationController();
    addTearDown(controller.dispose);
    var changes = 0;
    controller.addListener(() => changes += 1);

    controller.update(
      refreshSignal: 2,
      cue: const TodayOutputCue.idle(),
      captureCue: const TodayRekaCaptureCue.idle(),
    );
    controller.update(
      refreshSignal: 2,
      cue: const TodayOutputCue.idle(),
      captureCue: const TodayRekaCaptureCue.idle(),
    );

    expect(changes, 1);
    expect(controller.value.refreshSignal, 2);
  });
}
