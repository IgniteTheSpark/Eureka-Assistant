import 'package:eureka/theme_v2/foundation/theme_v2_motion.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Theme V2 color tokens', () {
    test('light palette matches the design source of truth', () {
      expect(ThemeV2Tokens.light.background, const Color(0xFFF7F9FC));
      expect(ThemeV2Tokens.light.surface, const Color(0xFFFFFFFF));
      expect(ThemeV2Tokens.light.foreground, const Color(0xFF101319));
      expect(ThemeV2Tokens.light.muted, const Color(0xFF6D7480));
      expect(ThemeV2Tokens.light.border, const Color(0xFFD9E0E8));
      expect(ThemeV2Tokens.light.accent, const Color(0xFF25B6D6));
      expect(ThemeV2Tokens.light.accentSoft, const Color(0xFFE9F8FC));
      expect(ThemeV2Tokens.light.critical, const Color(0xFFD23A57));
      expect(ThemeV2Tokens.light.watermark, const Color(0x09101319));
    });

    test('dark palette matches the design source of truth', () {
      expect(ThemeV2Tokens.dark.background, const Color(0xFF0B0D12));
      expect(ThemeV2Tokens.dark.surface, const Color(0xFF121620));
      expect(ThemeV2Tokens.dark.foreground, const Color(0xFFF3F5FA));
      expect(ThemeV2Tokens.dark.muted, const Color(0xFF8991A0));
      expect(ThemeV2Tokens.dark.border, const Color(0xFF29303D));
      expect(ThemeV2Tokens.dark.accent, const Color(0xFF8A82FF));
      expect(ThemeV2Tokens.dark.accentSoft, const Color(0xFF1A1D35));
      expect(ThemeV2Tokens.dark.critical, const Color(0xFFFF5F7B));
      expect(ThemeV2Tokens.dark.watermark, const Color(0x09FFFFFF));
    });

    test('light and dark use the same ThemeExtension type', () {
      expect(ThemeV2Tokens.light, isA<ThemeExtension<ThemeV2Tokens>>());
      expect(ThemeV2Tokens.dark, isA<ThemeExtension<ThemeV2Tokens>>());
      expect(
        ThemeV2Tokens.forBrightness(Brightness.light),
        same(ThemeV2Tokens.light),
      );
      expect(
        ThemeV2Tokens.forBrightness(Brightness.dark),
        same(ThemeV2Tokens.dark),
      );
    });
  });

  test('spacing, radii, touch target, and raw motion match the design', () {
    expect(
      const [
        ThemeV2Spacing.xs,
        ThemeV2Spacing.sm,
        ThemeV2Spacing.md,
        ThemeV2Spacing.lg,
        ThemeV2Spacing.xl,
      ],
      const [4.0, 8.0, 12.0, 16.0, 24.0],
    );
    expect(
      const [
        ThemeV2Radii.sm,
        ThemeV2Radii.md,
        ThemeV2Radii.lg,
        ThemeV2Radii.pill,
      ],
      const [7.0, 10.0, 14.0, 999.0],
    );
    expect(ThemeV2Sizes.minTouchTarget, 44);
    expect(
      ThemeV2MotionToken.fast.rawDuration,
      const Duration(milliseconds: 160),
    );
    expect(
      ThemeV2MotionToken.standard.rawDuration,
      const Duration(milliseconds: 260),
    );
    expect(
      ThemeV2MotionToken.fluid.rawDuration,
      const Duration(milliseconds: 420),
    );
    expect(ThemeV2Motion.easeFluid, const Cubic(0.22, 1, 0.36, 1));
  });
}
