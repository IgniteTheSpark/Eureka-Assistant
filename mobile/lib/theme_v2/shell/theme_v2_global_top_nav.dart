import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/theme_controller.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'device_status_summary.dart';
import 'theme_v2_floating_dock.dart';

class ThemeV2GlobalTopNav extends StatelessWidget {
  const ThemeV2GlobalTopNav({
    super.key,
    required this.deviceStatus,
    required this.onDeviceSelected,
    required this.onNotificationsPressed,
    this.unreadNotificationCount = 0,
    this.transparentSurface = false,
    this.floatingDock = false,
  });

  final DeviceStatusSummary deviceStatus;
  final ValueChanged<ThemeV2DeviceTarget> onDeviceSelected;
  final VoidCallback onNotificationsPressed;
  final int unreadNotificationCount;
  final bool transparentSurface;
  final bool floatingDock;
  static const double height = 56;
  static const floatingDockKey = Key('theme-v2-floating-top-dock');
  static const double floatingHorizontalInset = 16;
  static const double floatingVerticalInset = 8;
  static const double floatingContentHeight = 60;
  static const double floatingExtent = 76;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final content = _TopNavContent(
      deviceStatus: deviceStatus,
      onDeviceSelected: onDeviceSelected,
      onNotificationsPressed: onNotificationsPressed,
      unreadNotificationCount: unreadNotificationCount,
    );
    if (floatingDock) {
      return SizedBox(
        height: floatingExtent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: floatingHorizontalInset,
            vertical: floatingVerticalInset,
          ),
          child: Material(
            key: floatingDockKey,
            elevation: ThemeV2FloatingDock.elevation,
            shadowColor: ThemeV2FloatingDock.lightShadowColor,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                ThemeV2FloatingDock.lightRadius,
              ),
              side: BorderSide(color: tokens.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(height: floatingContentHeight, child: content),
          ),
        ),
      );
    }
    return Material(
      color: transparentSurface ? Colors.transparent : tokens.background,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: content,
      ),
    );
  }
}

class _TopNavContent extends StatelessWidget {
  const _TopNavContent({
    required this.deviceStatus,
    required this.onDeviceSelected,
    required this.onNotificationsPressed,
    required this.unreadNotificationCount,
  });

  final DeviceStatusSummary deviceStatus;
  final ValueChanged<ThemeV2DeviceTarget> onDeviceSelected;
  final VoidCallback onNotificationsPressed;
  final int unreadNotificationCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.lg),
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
                onDeviceSelected: onDeviceSelected,
                maxWidth: narrow ? 100 : 124,
              ),
              const SizedBox(width: ThemeV2Spacing.xs),
              const _ThemeV2ThemeToggle(),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ThemeV2IconButton(
                    semanticLabel: unreadNotificationCount > 0
                        ? '通知，$unreadNotificationCount 条未读'
                        : '通知',
                    icon: Icons.notifications_none_outlined,
                    color: tokens.muted,
                    onPressed: onNotificationsPressed,
                  ),
                  if (unreadNotificationCount > 0)
                    Positioned(
                      right: 1,
                      top: 2,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: tokens.critical,
                              borderRadius: BorderRadius.circular(
                                ThemeV2Radii.pill,
                              ),
                              border: Border.all(
                                color: tokens.background,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              unreadNotificationCount > 99
                                  ? '99+'
                                  : '$unreadNotificationCount',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: tokens.background,
                                    fontSize: 8,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
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
    required this.onDeviceSelected,
    required this.maxWidth,
  });

  final DeviceStatusSummary summary;
  final ValueChanged<ThemeV2DeviceTarget> onDeviceSelected;
  final double maxWidth;

  Future<void> _handlePressed(BuildContext context) async {
    final directTarget = summary.directTarget;
    if (directTarget != null) {
      onDeviceSelected(directTarget);
      return;
    }

    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final buttonOrigin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final anchor = Rect.fromLTWH(
      buttonOrigin.dx,
      buttonOrigin.dy + button.size.height,
      button.size.width,
      0,
    );
    final selected = await showMenu<ThemeV2DeviceTarget>(
      context: context,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(
          value: ThemeV2DeviceTarget.card,
          child: _DeviceMenuRow(
            icon: Icons.contactless_outlined,
            name: 'UReka 录音卡',
          ),
        ),
        PopupMenuItem(
          value: ThemeV2DeviceTarget.ring,
          child: _DeviceMenuRow(icon: Icons.circle_outlined, name: 'UReka 戒指'),
        ),
      ],
    );
    if (selected != null && context.mounted) {
      onDeviceSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final color = switch (summary.kind) {
      DeviceStatusSummaryKind.connected => tokens.accent,
      DeviceStatusSummaryKind.attention => tokens.critical,
      DeviceStatusSummaryKind.disconnected => tokens.muted,
    };
    final semanticLabel = '设备：${summary.label}';
    final iconOnly = summary.presence != ThemeV2DevicePresence.none;

    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: () => _handlePressed(context),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: ThemeV2Sizes.minTouchTarget,
            minWidth: ThemeV2Sizes.minTouchTarget,
            maxWidth: iconOnly ? ThemeV2Sizes.minTouchTarget : maxWidth,
          ),
          child: Material(
            color: tokens.accentSoft,
            borderRadius: BorderRadius.circular(
              iconOnly ? ThemeV2Radii.md : ThemeV2Radii.pill,
            ),
            child: InkWell(
              onTap: () => _handlePressed(context),
              borderRadius: BorderRadius.circular(
                iconOnly ? ThemeV2Radii.md : ThemeV2Radii.pill,
              ),
              child: Padding(
                padding: iconOnly
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.md),
                child: iconOnly
                    ? Center(child: connectedGlyph(summary.presence, color))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          connectedGlyph(summary.presence, color),
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

class _DeviceMenuRow extends StatelessWidget {
  const _DeviceMenuRow({required this.icon, required this.name});

  final IconData icon;
  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      children: [
        Icon(icon, size: 20, color: tokens.accent),
        const SizedBox(width: ThemeV2Spacing.sm),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name),
            Text(
              '已连接',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ],
        ),
      ],
    );
  }
}

Widget connectedGlyph(ThemeV2DevicePresence presence, Color color) {
  return switch (presence) {
    ThemeV2DevicePresence.card => Icon(
      Icons.contactless_outlined,
      size: 20,
      color: color,
    ),
    ThemeV2DevicePresence.ring => Icon(
      Icons.circle_outlined,
      size: 20,
      color: color,
    ),
    ThemeV2DevicePresence.both => Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(-4, 3),
          child: Icon(Icons.contactless_outlined, size: 15, color: color),
        ),
        Transform.translate(
          offset: const Offset(5, -4),
          child: Icon(Icons.circle_outlined, size: 15, color: color),
        ),
      ],
    ),
    ThemeV2DevicePresence.none => Icon(
      Icons.devices_outlined,
      size: 18,
      color: color,
    ),
  };
}
