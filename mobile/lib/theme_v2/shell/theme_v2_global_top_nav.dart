import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/theme_controller.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'device_status_summary.dart';

class ThemeV2GlobalTopNav extends StatelessWidget {
  const ThemeV2GlobalTopNav({
    super.key,
    required this.deviceStatus,
    required this.onDevicePressed,
    required this.onNotificationsPressed,
  });

  final DeviceStatusSummary deviceStatus;
  final VoidCallback onDevicePressed;
  final VoidCallback onNotificationsPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.background,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.lg),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 380;
            return Row(
              children: [
                Semantics(
                  label: 'UReka logo',
                  image: true,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: narrow ? 68 : 84,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SvgPicture.asset(
                          'assets/logo/eureka_wordmark.svg',
                          height: 18,
                          colorFilter: ColorFilter.mode(
                            tokens.accent,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                _DeviceStatusButton(
                  summary: deviceStatus,
                  onPressed: onDevicePressed,
                  maxWidth: narrow ? 100 : 124,
                ),
                const SizedBox(width: ThemeV2Spacing.xs),
                const _ThemeV2ThemeToggle(),
                ThemeV2IconButton(
                  semanticLabel: '通知',
                  icon: Icons.notifications_none_outlined,
                  color: tokens.muted,
                  onPressed: onNotificationsPressed,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThemeV2ThemeToggle extends StatelessWidget {
  const _ThemeV2ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        final dark = mode == ThemeMode.dark;
        return ThemeV2IconButton(
          semanticLabel: dark ? '切换到日间' : '切换到夜间',
          icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          color: tokens.muted,
          onPressed: toggleThemeMode,
        );
      },
    );
  }
}

class _DeviceStatusButton extends StatelessWidget {
  const _DeviceStatusButton({
    required this.summary,
    required this.onPressed,
    required this.maxWidth,
  });

  final DeviceStatusSummary summary;
  final VoidCallback onPressed;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final color = switch (summary.kind) {
      DeviceStatusSummaryKind.connected => tokens.accent,
      DeviceStatusSummaryKind.attention => tokens.critical,
      DeviceStatusSummaryKind.disconnected => tokens.muted,
    };
    final icon = switch (summary.kind) {
      DeviceStatusSummaryKind.connected => Icons.devices,
      DeviceStatusSummaryKind.attention => Icons.error_outline,
      DeviceStatusSummaryKind.disconnected => Icons.devices_outlined,
    };
    final semanticLabel = '设备：${summary.label}';

    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: ThemeV2Sizes.minTouchTarget,
            minWidth: ThemeV2Sizes.minTouchTarget,
            maxWidth: maxWidth,
          ),
          child: Material(
            color: tokens.accentSoft,
            borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeV2Spacing.md,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: ThemeV2Spacing.sm),
                    Flexible(
                      child: Text(
                        summary.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
