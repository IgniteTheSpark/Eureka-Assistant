import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'calendar_components.dart';

class CalendarStickyDateRail extends StatelessWidget {
  const CalendarStickyDateRail({
    super.key,
    required this.day,
    required this.today,
    required this.itemCount,
    required this.flashCount,
    required this.onTapDate,
    required this.onOpenFlash,
    this.pushOffset = 0,
  });

  final DateTime day;
  final DateTime today;
  final int itemCount;
  final int flashCount;
  final VoidCallback onTapDate;
  final VoidCallback onOpenFlash;
  final double pushOffset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final isToday = calendarDayKey(day) == calendarDayKey(today);
    return Transform.translate(
      offset: Offset(0, pushOffset),
      child: SizedBox(
        key: const ValueKey('calendar-sticky-date-rail'),
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '${day.month}月${day.day}日，打开日期',
              button: true,
              onTap: onTapDate,
              child: ExcludeSemantics(
                child: ThemeV2HitTarget(
                  child: InkWell(
                    key: ValueKey('calendar-date-${calendarDayKey(day)}'),
                    onTap: onTapDate,
                    child: Padding(
                      padding: const EdgeInsets.only(left: ThemeV2Spacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${day.month}月',
                            style: ThemeV2Typography.mono(
                              fontSize: 9,
                              color: tokens.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            day.day.toString().padLeft(2, '0'),
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: isToday
                                      ? tokens.accent
                                      : tokens.foreground,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                          ),
                          Text(
                            '${_weekday(day)} · $itemCount 项',
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: tokens.muted, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (flashCount > 0)
              Padding(
                padding: const EdgeInsets.only(
                  top: ThemeV2Spacing.sm,
                  left: ThemeV2Spacing.xs,
                ),
                child: Semantics(
                  label: '打开 ${day.month}月${day.day}日闪念，共 $flashCount 条',
                  button: true,
                  onTap: onOpenFlash,
                  child: ExcludeSemantics(
                    child: ThemeV2HitTarget(
                      child: InkWell(
                        key: ValueKey('calendar-flash-${calendarDayKey(day)}'),
                        onTap: onOpenFlash,
                        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.accentSoft,
                            borderRadius: BorderRadius.circular(
                              ThemeV2Radii.pill,
                            ),
                            border: Border.all(color: tokens.accent),
                          ),
                          child: SizedBox(
                            width: 44,
                            height: 28,
                            child: Center(
                              child: Text(
                                '✦ $flashCount',
                                style: ThemeV2Typography.mono(
                                  fontSize: 9,
                                  color: tokens.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _weekday(DateTime value) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][value.weekday - 1];
}
