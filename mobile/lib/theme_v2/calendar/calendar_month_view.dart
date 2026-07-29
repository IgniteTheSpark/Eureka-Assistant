import 'package:flutter/material.dart';

import '../../timeline/timeline.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'calendar_components.dart';
import 'calendar_controller.dart';
import 'calendar_models.dart';

class CalendarMonthView extends StatefulWidget {
  const CalendarMonthView({
    super.key,
    required this.month,
    required this.data,
    required this.controller,
    required this.today,
    required this.onOpenDay,
    required this.onOpenRecord,
    this.onMonthChanged,
  });

  final DateTime month;
  final CalendarData data;
  final CalendarController controller;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final ValueChanged<DateTime>? onMonthChanged;

  @override
  State<CalendarMonthView> createState() => _CalendarMonthViewState();
}

class _CalendarMonthViewState extends State<CalendarMonthView> {
  late DateTime _month = DateTime(widget.month.year, widget.month.month);

  @override
  void didUpdateWidget(CalendarMonthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month) {
      _month = DateTime(widget.month.year, widget.month.month);
    }
  }

  void _moveMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    widget.onMonthChanged?.call(_month);
  }

  void _tapDate(DateTime day) {
    final selected = widget.controller.selectedDate;
    if (selected != null && calendarDayKey(selected) == calendarDayKey(day)) {
      widget.onOpenDay(day);
    } else {
      widget.controller.changeDate(day);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final selected = widget.controller.selectedDate ?? widget.today;
    final selectedRecords =
        widget.data.byDay[calendarDayOf(selected)] ?? const <TimelineItem>[];
    return Container(
      key: const ValueKey('calendar-month-view'),
      color: tokens.background,
      padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            key: ValueKey('calendar-month-top-gap'),
            height: ThemeV2Spacing.xs,
          ),
          _ProgressiveHeader(
            title: '${_month.year}年${_month.month}月',
            onPrevious: () => _moveMonth(-1),
            onToday: () {
              setState(
                () => _month = DateTime(widget.today.year, widget.today.month),
              );
              widget.onMonthChanged?.call(_month);
            },
            onNext: () => _moveMonth(1),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          const _WeekdayHeader(),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = constraints.maxWidth / 7;
              final cellHeight = (cellWidth * 0.82).clamp(38.0, 52.0);
              final cells = _monthCells(_month);
              return SizedBox(
                key: const ValueKey('calendar-month-grid'),
                height: cellHeight * 6,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: cellWidth / cellHeight,
                  ),
                  itemCount: cells.length,
                  itemBuilder: (context, index) {
                    final day = cells[index];
                    final items =
                        widget.data.byDay[calendarDayOf(day)] ??
                        const <TimelineItem>[];
                    return _MonthCell(
                      day: day,
                      inMonth: day.month == _month.month,
                      selected: calendarDayKey(day) == calendarDayKey(selected),
                      today:
                          calendarDayKey(day) == calendarDayKey(widget.today),
                      count: items.length,
                      onTap: () => _tapDate(day),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: ThemeV2Spacing.md),
          Expanded(
            child: _ProgressiveDaySummary(
              day: selected,
              items: selectedRecords,
              skills: widget.data.skills,
              onOpenRecord: widget.onOpenRecord,
            ),
          ),
        ],
      ),
    );
  }

  static List<DateTime> _monthCells(DateTime month) {
    final first = DateTime(month.year, month.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    return [
      for (var index = 0; index < 42; index++) start.add(Duration(days: index)),
    ];
  }
}

class _ProgressiveHeader extends StatelessWidget {
  const _ProgressiveHeader({
    required this.title,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
  });

  final String title;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        ThemeV2IconButton(
          semanticLabel: '上一个月',
          icon: Icons.chevron_left,
          onPressed: onPrevious,
          color: tokens.muted,
        ),
        Semantics(
          label: '回到今天',
          button: true,
          onTap: onToday,
          child: ExcludeSemantics(
            child: ThemeV2HitTarget(
              child: InkWell(
                onTap: onToday,
                child: Center(
                  child: Text(
                    'TODAY',
                    style: ThemeV2Typography.mono(
                      fontSize: 8,
                      color: tokens.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ThemeV2IconButton(
          semanticLabel: '下一个月',
          icon: Icons.chevron_right,
          onPressed: onNext,
          color: tokens.muted,
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      children: [
        for (final day in const [
          'MON',
          'TUE',
          'WED',
          'THU',
          'FRI',
          'SAT',
          'SUN',
        ])
          Expanded(
            child: Center(
              child: Text(
                day,
                style: ThemeV2Typography.mono(
                  fontSize: 7,
                  color: tokens.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool today;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '${day.month}月${day.day}日，$count 项',
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: InkWell(
            key: ValueKey('calendar-month-${calendarDayKey(day)}'),
            onTap: onTap,
            child: Center(
              child: Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? tokens.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
                  border: selected
                      ? Border.all(color: tokens.accent)
                      : today
                      ? Border.all(color: tokens.foreground)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      day.day.toString().padLeft(2, '0'),
                      style: ThemeV2Typography.mono(
                        fontSize: 10,
                        color: !inMonth
                            ? tokens.muted.withValues(alpha: 0.45)
                            : selected
                            ? tokens.accent
                            : tokens.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (count > 0)
                      Container(
                        key: ValueKey(
                          'calendar-month-activity-${calendarDayKey(day)}',
                        ),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: selected ? tokens.accent : tokens.muted,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      const SizedBox(height: 4),
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

class _ProgressiveDaySummary extends StatelessWidget {
  const _ProgressiveDaySummary({
    required this.day,
    required this.items,
    required this.skills,
    required this.onOpenRecord,
  });

  final DateTime day;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final ValueChanged<CalendarRecord> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final records = items
        .where((item) => item.kind != 'input_turn')
        .map(CalendarRecord.fromTimeline)
        .toList(growable: false);
    final flashCount = items.where((item) => item.kind == 'input_turn').length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeV2Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                day.day.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: tokens.foreground,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: ThemeV2Spacing.sm),
              Text(
                '${_weekday(day)} · ${records.length} 条记录',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
              const Spacer(),
              if (flashCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ThemeV2Spacing.md,
                    vertical: ThemeV2Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    border: Border.all(color: tokens.accent),
                  ),
                  child: Text(
                    '⚡ 闪念 $flashCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Text(
                      '这一天没有记录',
                      style: TextStyle(color: tokens.muted),
                    ),
                  )
                : ListView(
                    children: [
                      for (final record in records)
                        CalendarRecordRow(
                          record: record,
                          skills: skills,
                          onTap: () => onOpenRecord(record),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime day) =>
      const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][day.weekday - 1];
}
