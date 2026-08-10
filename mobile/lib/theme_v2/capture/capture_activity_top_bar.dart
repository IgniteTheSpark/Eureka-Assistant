import 'package:flutter/material.dart';

import '../../capture_activity/capture_activity_event.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../shell/theme_v2_global_top_nav.dart';
import 'capture_activity_models.dart';
import 'thinking_orb.dart';

@immutable
class CaptureTopBarPalette {
  const CaptureTopBarPalette({
    required this.background,
    required this.backgroundEnd,
    required this.lightBand,
  });

  final Color background;
  final Color backgroundEnd;
  final List<Color> lightBand;
}

CaptureTopBarPalette captureTopBarPalette(Brightness brightness) =>
    brightness == Brightness.dark
    ? const CaptureTopBarPalette(
        background: Color(0xFF0B1326),
        backgroundEnd: Color(0xFF24152F),
        lightBand: [Color(0xFFFFCA6B), Color(0xFFFF68B5), Color(0xFF4EE7FF)],
      )
    : const CaptureTopBarPalette(
        background: Color(0xFFF8FCFF),
        backgroundEnd: Color(0xFFEEE9FF),
        lightBand: [Color(0xFF7F68F2), Color(0xFFFF7789), Color(0xFFFFC56A)],
      );

class CaptureActivityTopBar extends StatefulWidget {
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
  State<CaptureActivityTopBar> createState() => _CaptureActivityTopBarState();
}

class _CaptureActivityTopBarState extends State<CaptureActivityTopBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lightBand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _lightBand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final palette = captureTopBarPalette(Theme.of(context).brightness);
    final enabled = widget.item.canOpenSession && widget.onTap != null;
    return SizedBox(
      key: CaptureActivityTopBar.rootKey,
      height: ThemeV2GlobalTopNav.height,
      child: Material(
        color: palette.background,
        child: InkWell(
          onTap: enabled ? widget.onTap : null,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _lightBand,
              builder: (context, child) {
                final travel = -1.8 + _lightBand.value * 3.6;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [palette.background, palette.backgroundEnd],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    border: Border(bottom: BorderSide(color: tokens.border)),
                  ),
                  child: DecoratedBox(
                    key: const ValueKey('capture-activity-light-band'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(travel - 1.2, -0.5),
                        end: Alignment(travel + 1.2, 0.5),
                        colors: [
                          Colors.transparent,
                          palette.lightBand[0].withValues(alpha: 0.18),
                          palette.lightBand[1].withValues(alpha: 0.22),
                          palette.lightBand[2].withValues(alpha: 0.17),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.28, 0.5, 0.72, 1],
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeV2Spacing.lg,
                ),
                child: Row(
                  children: [
                    ThinkingOrb(
                      state: thinkingOrbStateForCapture(widget.item.phase),
                      size: 32,
                    ),
                    const SizedBox(width: ThemeV2Spacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.source.label,
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
                            widget.item.statusLabel,
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
                    if (widget.queuedCount > 0) ...[
                      const SizedBox(width: ThemeV2Spacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ThemeV2Spacing.sm,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.background.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(
                            ThemeV2Radii.pill,
                          ),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          '另有 ${widget.queuedCount} 条',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
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
      ),
    );
  }
}
