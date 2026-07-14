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
}
