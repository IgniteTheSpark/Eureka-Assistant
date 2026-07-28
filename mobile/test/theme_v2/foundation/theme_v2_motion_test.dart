import 'package:eureka/theme_v2/foundation/theme_v2_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in const {
    ThemeV2MotionToken.fast: Duration(milliseconds: 160),
    ThemeV2MotionToken.standard: Duration(milliseconds: 260),
    ThemeV2MotionToken.fluid: Duration(milliseconds: 420),
  }.entries) {
    testWidgets(
      '${entry.key.name} returns its raw duration when motion is on',
      (tester) async {
        late Duration actual;

        await tester.pumpWidget(
          _MotionHost(
            disableAnimations: false,
            builder: (context) {
              actual = ThemeV2Motion.duration(context, entry.key);
              return const SizedBox.shrink();
            },
          ),
        );

        expect(actual, entry.value);
      },
    );
  }

  testWidgets('all motion tokens return zero when animations are disabled', (
    tester,
  ) async {
    late List<Duration> actual;

    await tester.pumpWidget(
      _MotionHost(
        disableAnimations: true,
        builder: (context) {
          actual = [
            for (final token in ThemeV2MotionToken.values)
              ThemeV2Motion.duration(context, token),
          ];
          return const SizedBox.shrink();
        },
      ),
    );

    expect(actual, everyElement(Duration.zero));
  });
}

class _MotionHost extends StatelessWidget {
  const _MotionHost({required this.disableAnimations, required this.builder});

  final bool disableAnimations;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Builder(builder: builder),
    );
  }
}
