import 'package:flutter/material.dart';

import '../../timeline/timeline.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'calendar_mode_state.dart';
import 'calendar_models.dart';

String calendarDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

String calendarTimeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String calendarDistanceLabel(DateTime day, DateTime today) {
  final target = calendarDayOf(day);
  final origin = calendarDayOf(today);
  if (target == origin) return 'TODAY';

  final later = target.isAfter(origin);
  final earlierDate = later ? origin : target;
  final laterDate = later ? target : origin;
  final months = _completeCalendarMonths(earlierDate, laterDate);
  final String unit;
  final int value;
  if (months >= 12) {
    value = months ~/ 12;
    unit = 'YEAR';
  } else if (months >= 1) {
    value = months;
    unit = 'MONTH';
  } else {
    final days = laterDate.difference(earlierDate).inDays;
    if (days >= 7) {
      value = days ~/ 7;
      unit = 'WEEK';
    } else {
      value = days;
      unit = 'DAY';
    }
  }
  final plural = value == 1 ? '' : 'S';
  return '$value $unit$plural ${later ? 'LATER' : 'AGO'}';
}

int _completeCalendarMonths(DateTime earlier, DateTime later) {
  var months = (later.year - earlier.year) * 12 + later.month - earlier.month;
  if (later.day < earlier.day) months--;
  return months.clamp(0, 1 << 30);
}

class CalendarModeControl extends StatelessWidget {
  const CalendarModeControl({
    super.key,
    required this.mode,
    required this.onSelected,
  });

  final CalendarMode mode;
  final ValueChanged<CalendarMode> onSelected;

  static const _options = <(CalendarMode, String, String)>[
    (CalendarMode.flow, '流', '流视图'),
    (CalendarMode.month, '月', '月视图'),
    (CalendarMode.year, '年', '年视图'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in _options)
            Semantics(
              label: option.$3,
              button: true,
              selected: option.$1 == mode,
              onTap: () => onSelected(option.$1),
              child: ExcludeSemantics(
                child: ThemeV2HitTarget(
                  child: InkWell(
                    onTap: () => onSelected(option.$1),
                    borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    child: Container(
                      width: 48,
                      height: ThemeV2Sizes.minTouchTarget,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: option.$1 == mode
                            ? tokens.accentSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                      ),
                      child: Text(
                        option.$2,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: option.$1 == mode
                                  ? tokens.accent
                                  : tokens.muted,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CalendarUntimedDivider extends StatelessWidget {
  const CalendarUntimedDivider({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      key: ValueKey('calendar-untimed-divider-$recordId'),
      height: 20,
      child: Row(
        children: [
          Expanded(child: Divider(color: tokens.border, height: 1)),
          const SizedBox(width: ThemeV2Spacing.sm),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: tokens.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: ThemeV2Spacing.sm),
          SizedBox(width: 36, child: Divider(color: tokens.border, height: 1)),
        ],
      ),
    );
  }
}

class CalendarRecordRow extends StatelessWidget {
  const CalendarRecordRow({
    super.key,
    required this.record,
    required this.skills,
    required this.onTap,
    this.muted = false,
  });

  final CalendarRecord record;
  final Map<String, SkillMeta> skills;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final item = record.item;
    final meta = item.kind == 'input_turn'
        ? null
        : resolveTimelineItemMeta(item, skills);
    return Semantics(
      label:
          '${record.isTimed ? calendarTimeLabel(record.effectiveAt) : '未指定时间'} ${item.title}',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: InkWell(
            key: ValueKey('calendar-record-${record.id}'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ThemeV2Spacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      record.isTimed
                          ? calendarTimeLabel(record.effectiveAt)
                          : '—',
                      style: ThemeV2Typography.mono(
                        fontSize: 9,
                        color: tokens.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (meta == null)
                    Icon(
                      Icons.bolt_outlined,
                      size: 16,
                      color: muted ? tokens.muted : tokens.accent,
                    )
                  else
                    Text(meta.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: ThemeV2Spacing.sm),
                  Expanded(
                    child: Text(
                      item.title.isEmpty ? '记录' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted ? tokens.muted : tokens.foreground,
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
    );
  }
}
