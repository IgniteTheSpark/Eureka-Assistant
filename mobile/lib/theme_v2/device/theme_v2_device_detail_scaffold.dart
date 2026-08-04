import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

@immutable
class ThemeV2DeviceInfoRow {
  const ThemeV2DeviceInfoRow({required this.label, required this.value});

  final String label;
  final String value;
}

class ThemeV2DeviceDetailScaffold extends StatelessWidget {
  const ThemeV2DeviceDetailScaffold({
    super.key,
    required this.title,
    required this.deviceName,
    required this.connected,
    required this.hero,
    required this.information,
    required this.unbinding,
    required this.onUnbind,
  });

  final String title;
  final String deviceName;
  final bool connected;
  final Widget hero;
  final List<ThemeV2DeviceInfoRow> information;
  final bool unbinding;
  final VoidCallback? onUnbind;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.foreground,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.lg,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.lg,
          ThemeV2Spacing.xl,
        ),
        children: [
          SizedBox(
            key: const ValueKey('device-detail-hero'),
            height: 180,
            child: Center(child: hero),
          ),
          const SizedBox(height: ThemeV2Spacing.lg),
          Text(
            deviceName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: tokens.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          Center(child: _ConnectionBadge(connected: connected)),
          const SizedBox(height: ThemeV2Spacing.xl),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
            ),
            child: Column(
              children: [
                for (var index = 0; index < information.length; index++) ...[
                  _InformationRow(row: information[index]),
                  if (index != information.length - 1)
                    Divider(height: 1, color: tokens.border),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.lg,
          ThemeV2Spacing.md,
          ThemeV2Spacing.lg,
          ThemeV2Spacing.lg,
        ),
        child: SizedBox(
          height: ThemeV2Sizes.minTouchTarget,
          child: FilledButton(
            onPressed: unbinding ? null : onUnbind,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.critical,
              foregroundColor: tokens.surface,
              disabledBackgroundColor: tokens.critical.withValues(alpha: 0.45),
              disabledForegroundColor: tokens.surface.withValues(alpha: 0.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              ),
            ),
            child: unbinding
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.surface,
                    ),
                  )
                : const Text('解除绑定'),
          ),
        ),
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: connected
            ? tokens.accentSoft
            : tokens.muted.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ThemeV2Spacing.md,
          vertical: ThemeV2Spacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 8,
              color: connected ? tokens.accent : tokens.muted,
            ),
            const SizedBox(width: ThemeV2Spacing.sm),
            Text(
              connected ? '已连接' : '未连接',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: connected ? tokens.accent : tokens.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.row});

  final ThemeV2DeviceInfoRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeV2Spacing.lg,
        vertical: ThemeV2Spacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              row.label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
            ),
          ),
          const SizedBox(width: ThemeV2Spacing.lg),
          Flexible(
            child: Text(
              row.value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
