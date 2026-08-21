import 'package:eureka/theme_v2/capture/reka_terminal_models.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/shell/reka_mini.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native mini Reka keeps exact visual and target geometry', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_mini()));

    expect(
      tester.getSize(find.byKey(RekaMini.targetKey)),
      const Size.square(72),
    );
    expect(tester.getSize(find.byKey(RekaMini.visualKey)), const Size(66, 48));
    expect(find.byKey(RekaMini.shellKey), findsOneWidget);
    expect(find.byKey(RekaMini.visorKey), findsOneWidget);
  });

  test('eye patterns distinguish non-color capture states', () {
    expect(
      rekaMiniEyePattern(RekaTerminalPhase.listening, left: true),
      isNot(rekaMiniEyePattern(RekaTerminalPhase.cancelArmed, left: true)),
    );
    expect(
      rekaMiniEyePattern(RekaTerminalPhase.receiving, left: true),
      isNot(rekaMiniEyePattern(RekaTerminalPhase.receiving, left: false)),
    );
    expect(
      rekaMiniEyePattern(RekaTerminalPhase.done, left: true),
      isNot(rekaMiniEyePattern(RekaTerminalPhase.failed, left: true)),
    );
  });

  testWidgets('long press reports movement and never also taps', (
    tester,
  ) async {
    var taps = 0;
    var starts = 0;
    var ends = 0;
    final offsets = <double>[];
    await tester.pumpWidget(
      _host(
        _mini(
          phase: RekaTerminalPhase.listening,
          onTap: (_) => taps++,
          onLongPressStart: () => starts++,
          onLongPressMove: offsets.add,
          onLongPressEnd: () => ends++,
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(RekaMini.targetKey)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect((starts, ends, taps), (1, 1, 0));
    expect(offsets.last, closeTo(-80, .01));
  });

  testWidgets('reduced motion leaves no repeating mini Reka ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_mini(phase: RekaTerminalPhase.listening), disableAnimations: true),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

RekaMini _mini({
  RekaTerminalPhase? phase,
  ValueChanged<Rect>? onTap,
  VoidCallback? onLongPressStart,
  ValueChanged<double>? onLongPressMove,
  VoidCallback? onLongPressEnd,
}) => RekaMini(
  phase: phase,
  onTap: onTap ?? (_) {},
  onLongPressStart: onLongPressStart ?? () {},
  onLongPressMove: onLongPressMove ?? (_) {},
  onLongPressEnd: onLongPressEnd ?? () {},
  onLongPressCancel: () {},
);

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);
