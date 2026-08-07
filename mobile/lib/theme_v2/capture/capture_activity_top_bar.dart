import 'package:flutter/material.dart';

import '../../capture_activity/capture_activity_event.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../shell/theme_v2_global_top_nav.dart';
import 'capture_activity_models.dart';
import 'thinking_orb.dart';

class CaptureActivityTopBar extends StatelessWidget {
  const CaptureActivityTopBar({
    super.key,
    required this.item,
    required this.queuedCount,
    this.onTap,
  });

  static const rootKey = ValueKey<String>('capture-activity-top-bar');

  final CaptureActivityItem item;
  final int queuedCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final enabled = item.canOpenSession && onTap != null;
    return SizedBox(
      key: rootKey,
      height: ThemeV2GlobalTopNav.height,
      child: Material(
        color: tokens.surface,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.surface, tokens.accentSoft],
                stops: const [0.18, 1],
              ),
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.lg,
              ),
              child: Row(
                children: [
                  ThinkingOrb(phase: item.phase, size: 32),
                  const SizedBox(width: ThemeV2Spacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.source.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: tokens.muted,
                                fontSize: 9,
                                height: 1.05,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: tokens.foreground,
                                height: 1.05,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (queuedCount > 0) ...[
                    const SizedBox(width: ThemeV2Spacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ThemeV2Spacing.sm,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.background.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Text(
                        '另有 $queuedCount 条',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ] else if (enabled)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: tokens.muted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
