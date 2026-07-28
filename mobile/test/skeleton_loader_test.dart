import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/widgets/skeleton_loader.dart';

void main() {
  testWidgets('three-line skeleton card fits the compact list height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: USkeletonCard(height: 76),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'skeleton disposes and recreates its ticker when reduced motion changes',
    (tester) async {
      const skeletonKey = ValueKey('motion-aware-skeleton');

      Future<void> pumpSkeleton({required bool disableAnimations}) {
        return tester.pumpWidget(
          MaterialApp(
            theme: buildEurekaTheme(EurekaColors.light),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: const Scaffold(
                body: USkeleton(key: skeletonKey, width: 120, height: 16),
              ),
            ),
          ),
        );
      }

      await pumpSkeleton(disableAnimations: false);
      final animatedSkeleton = find.descendant(
        of: find.byKey(skeletonKey),
        matching: find.byType(AnimatedBuilder),
      );
      final firstController =
          tester.widget<AnimatedBuilder>(animatedSkeleton).animation
              as AnimationController;
      expect(firstController.isAnimating, isTrue);

      await pumpSkeleton(disableAnimations: true);
      expect(find.byType(ShaderMask), findsNothing);
      expect(firstController.isAnimating, isFalse);

      await pumpSkeleton(disableAnimations: false);
      final secondController =
          tester.widget<AnimatedBuilder>(animatedSkeleton).animation
              as AnimationController;
      expect(secondController, isNot(same(firstController)));
      expect(secondController.isAnimating, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
