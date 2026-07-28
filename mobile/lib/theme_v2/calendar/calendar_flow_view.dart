import 'package:flutter/material.dart';

import '../../timeline/timeline.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'calendar_components.dart';
import 'calendar_controller.dart';
import 'calendar_models.dart';
import 'calendar_sticky_date_rail.dart';

class CalendarFlowView extends StatefulWidget {
  const CalendarFlowView({
    super.key,
    required this.data,
    required this.controller,
    required this.today,
    required this.onOpenDay,
    required this.onOpenRecord,
    required this.onOpenFlash,
  });

  final CalendarData data;
  final CalendarController controller;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final ValueChanged<DateTime> onOpenFlash;

  @override
  State<CalendarFlowView> createState() => _CalendarFlowViewState();
}

class _CalendarFlowViewState extends State<CalendarFlowView> {
  static const _pastDays = 3650;
  static const _futureDays = 3650;
  static const _dayExtent = 460.0;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _pastDays * _dayExtent,
  )..addListener(_onScroll);
  int _visibleIndex = _pastDays;
  double _railPushOffset = 0;

  DateTime get _firstDay =>
      calendarDayOf(widget.today).subtract(const Duration(days: _pastDays));

  DateTime _dayAt(int index) => _firstDay.add(Duration(days: index));

  void _onScroll() {
    final index = (_scroll.offset / _dayExtent).floor().clamp(
      0,
      _pastDays + _futureDays,
    );
    final remaining = _dayExtent - _scroll.offset % _dayExtent;
    final push = remaining < 136 ? remaining - 136 : 0.0;
    if (mounted && (index != _visibleIndex || push != _railPushOffset)) {
      setState(() {
        _visibleIndex = index;
        _railPushOffset = push;
      });
    }
  }

  void _tapDate(DateTime day) {
    final selected = widget.controller.selectedDate;
    if (selected != null && calendarDayKey(selected) == calendarDayKey(day)) {
      widget.onOpenDay(day);
      return;
    }
    widget.controller.changeDate(day);
    setState(() {});
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleDay = _dayAt(_visibleIndex);
    final visibleItems =
        widget.data.byDay[calendarDayOf(visibleDay)] ?? const <TimelineItem>[];
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(
            key: const ValueKey('calendar-flow-content'),
            child: ListView.builder(
              key: const ValueKey('calendar-flow-scroll'),
              controller: _scroll,
              itemExtent: _dayExtent,
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: _pastDays + _futureDays + 1,
              itemBuilder: (context, index) {
                final day = _dayAt(index);
                final items =
                    widget.data.byDay[calendarDayOf(day)] ??
                    const <TimelineItem>[];
                return _FlowDay(
                  day: day,
                  today: widget.today,
                  items: items,
                  skills: widget.data.skills,
                  showDateControl: index != _visibleIndex,
                  selected:
                      widget.controller.selectedDate != null &&
                      calendarDayKey(widget.controller.selectedDate!) ==
                          calendarDayKey(day),
                  onTapDate: () => _tapDate(day),
                  onOpenRecord: widget.onOpenRecord,
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: CalendarStickyDateRail(
            day: visibleDay,
            today: widget.today,
            itemCount: visibleItems.length,
            flashCount: visibleItems
                .where((item) => item.kind == 'input_turn')
                .length,
            pushOffset: _railPushOffset,
            onTapDate: () => _tapDate(visibleDay),
            onOpenFlash: () => widget.onOpenFlash(visibleDay),
          ),
        ),
      ],
    );
  }
}

class _FlowDay extends StatelessWidget {
  const _FlowDay({
    required this.day,
    required this.today,
    required this.items,
    required this.skills,
    required this.showDateControl,
    required this.selected,
    required this.onTapDate,
    required this.onOpenRecord,
  });

  final DateTime day;
  final DateTime today;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final bool showDateControl;
  final bool selected;
  final VoidCallback onTapDate;
  final ValueChanged<CalendarRecord> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final records = items
        .where((item) => item.kind != 'input_turn')
        .map(CalendarRecord.fromTimeline)
        .toList();
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned(
            right: ThemeV2Spacing.lg,
            top: ThemeV2Spacing.xs,
            child: IgnorePointer(
              child: Text(
                calendarDistanceLabel(day, today),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: tokens.watermark,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ),
          if (showDateControl)
            Positioned(
              left: ThemeV2Spacing.sm,
              top: ThemeV2Spacing.xs,
              child: _FlowDateControl(
                day: day,
                today: today,
                selected: selected,
                itemCount: items.length,
                onTap: onTapDate,
              ),
            ),
          Positioned(
            left: 84,
            right: ThemeV2Spacing.lg,
            top: 76,
            bottom: ThemeV2Spacing.lg,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.md,
              ),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: selected ? tokens.accent : tokens.border,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
              child: records.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        '空闲',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                      ),
                    )
                  : ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: [
                        for (final record in records) ...[
                          if (!record.isTimed)
                            CalendarUntimedDivider(recordId: record.id),
                          CalendarRecordRow(
                            record: record,
                            skills: skills,
                            muted: !record.isTimed,
                            onTap: () => onOpenRecord(record),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowDateControl extends StatelessWidget {
  const _FlowDateControl({
    required this.day,
    required this.today,
    required this.selected,
    required this.itemCount,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final bool selected;
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final isToday = calendarDayKey(day) == calendarDayKey(today);
    return Semantics(
      label: '${day.month}月${day.day}日',
      selected: selected,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: ValueKey('calendar-date-${calendarDayKey(day)}'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 60, minHeight: 68),
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
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: isToday || selected
                        ? tokens.accent
                        : tokens.foreground,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                Text(
                  '$itemCount 项',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
