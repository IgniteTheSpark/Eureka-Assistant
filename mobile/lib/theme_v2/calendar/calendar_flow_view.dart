import 'dart:math' as math;

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
    required this.onRequestManualRecord,
    required this.onOpenRecord,
    required this.onOpenFlash,
  });

  final CalendarData data;
  final CalendarController controller;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<DateTime> onRequestManualRecord;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final ValueChanged<DateTime> onOpenFlash;

  @override
  State<CalendarFlowView> createState() => _CalendarFlowViewState();
}

class _CalendarFlowViewState extends State<CalendarFlowView> {
  static const _pastDays = 3650;
  static const _futureDays = 3650;
  static const _minimumDayExtent = 180.0;
  int _visibleIndex = _pastDays;
  late double _visibleTop = _offsetForIndex(_visibleIndex);
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _visibleTop,
  )..addListener(_onScroll);
  double _railPushOffset = 0;
  DateTime? _manualConfirmationDay;

  DateTime get _firstDay =>
      calendarDayOf(widget.today).subtract(const Duration(days: _pastDays));

  DateTime _dayAt(int index) => _firstDay.add(Duration(days: index));

  double _dayExtent(int index) => _dayExtentFor(widget.data, index);

  double _dayExtentFor(CalendarData data, int index) {
    final dayData = data.day(_dayAt(index));
    final untimed = dayData.assets.where((record) => !record.isTimed).length;
    return math.max(
      _minimumDayExtent,
      128 + dayData.assetCount * 44 + untimed * 20,
    );
  }

  double _offsetForIndex(int index, {CalendarData? data}) {
    var offset = 0.0;
    for (var current = 0; current < index; current++) {
      offset += _dayExtentFor(data ?? widget.data, current);
    }
    return offset;
  }

  void _onScroll() {
    final offset = _scroll.offset;
    var index = _visibleIndex;
    var top = _visibleTop;
    while (index < _pastDays + _futureDays &&
        offset >= top + _dayExtent(index)) {
      top += _dayExtent(index);
      index++;
    }
    while (index > 0 && offset < top) {
      index--;
      top -= _dayExtent(index);
    }
    final remaining = top + _dayExtent(index) - offset;
    final push = remaining < 136 ? remaining - 136 : 0.0;
    if (mounted && (index != _visibleIndex || push != _railPushOffset)) {
      setState(() {
        _visibleIndex = index;
        _visibleTop = top;
        _railPushOffset = push;
      });
    }
  }

  void _activateDay(DateTime day) {
    final dayData = widget.data.day(day);
    widget.controller.changeDate(day);
    if (dayData.assetCount + dayData.flashCount > 0) {
      _manualConfirmationDay = null;
      widget.onOpenDay(day);
      return;
    }
    setState(() => _manualConfirmationDay = calendarDayOf(day));
  }

  void _requestManualRecord(DateTime day) {
    widget.controller.changeDate(day);
    widget.onRequestManualRecord(calendarDayOf(day));
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CalendarFlowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      final oldTop = _offsetForIndex(_visibleIndex, data: oldWidget.data);
      final intraDayOffset = _scroll.hasClients ? _scroll.offset - oldTop : 0.0;
      _visibleTop = _offsetForIndex(_visibleIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target = (_visibleTop + intraDayOffset).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        );
        if ((_scroll.offset - target).abs() > 0.5) {
          _scroll.jumpTo(target);
        }
        _onScroll();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleDay = _dayAt(_visibleIndex);
    final visibleDayData = widget.data.day(visibleDay);
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(
            key: const ValueKey('calendar-flow-content'),
            child: ListView.builder(
              key: const ValueKey('calendar-flow-scroll'),
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: _pastDays + _futureDays + 1,
              itemBuilder: (context, index) {
                final day = _dayAt(index);
                final items =
                    widget.data.byDay[calendarDayOf(day)] ??
                    const <TimelineItem>[];
                final confirmation =
                    _manualConfirmationDay != null &&
                    calendarDayKey(_manualConfirmationDay!) ==
                        calendarDayKey(day);
                return SizedBox(
                  height: _dayExtent(index),
                  child: _FlowDay(
                    day: day,
                    today: widget.today,
                    items: items,
                    skills: widget.data.skills,
                    showDateControl: index != _visibleIndex,
                    selected:
                        widget.controller.selectedDate != null &&
                        calendarDayKey(widget.controller.selectedDate!) ==
                            calendarDayKey(day),
                    showManualConfirmation: confirmation,
                    onActivateDay: () => _activateDay(day),
                    onRequestManualRecord: () => _requestManualRecord(day),
                    onOpenRecord: widget.onOpenRecord,
                    onOpenFlash: () => widget.onOpenFlash(day),
                  ),
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
            itemCount: visibleDayData.assetCount,
            flashCount: visibleDayData.flashCount,
            pushOffset: _railPushOffset,
            onTapDate: () => _activateDay(visibleDay),
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
    required this.showManualConfirmation,
    required this.onActivateDay,
    required this.onRequestManualRecord,
    required this.onOpenRecord,
    required this.onOpenFlash,
  });

  final DateTime day;
  final DateTime today;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final bool showDateControl;
  final bool selected;
  final bool showManualConfirmation;
  final VoidCallback onActivateDay;
  final VoidCallback onRequestManualRecord;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final VoidCallback onOpenFlash;

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
                itemCount: records.length,
                flashCount: items
                    .where((item) => item.kind == 'input_turn')
                    .length,
                onTap: onActivateDay,
                onOpenFlash: onOpenFlash,
              ),
            ),
          Positioned(
            left: 84,
            right: ThemeV2Spacing.lg,
            top: 76,
            bottom: ThemeV2Spacing.lg,
            child: GestureDetector(
              key: ValueKey('calendar-day-content-${calendarDayKey(day)}'),
              behavior: HitTestBehavior.opaque,
              onTap: onActivateDay,
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
                    ? showManualConfirmation
                          ? _ManualRecordConfirmation(
                              day: day,
                              onTap: onRequestManualRecord,
                            )
                          : const SizedBox.expand()
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
          ),
        ],
      ),
    );
  }
}

class _ManualRecordConfirmation extends StatelessWidget {
  const _ManualRecordConfirmation({required this.day, required this.onTap});

  final DateTime day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Align(
      key: ValueKey('calendar-empty-confirmation-${calendarDayKey(day)}'),
      alignment: Alignment.topLeft,
      child: Semantics(
        label: '${day.month}月${day.day}日，暂无记录，手动记录',
        button: true,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            child: InkWell(
              key: ValueKey('calendar-empty-manual-${calendarDayKey(day)}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: ThemeV2Sizes.minTouchTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeV2Spacing.md,
                  vertical: ThemeV2Spacing.sm,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: tokens.accent,
                    ),
                    const SizedBox(width: ThemeV2Spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${day.month}月${day.day}日 · 暂无记录',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.foreground),
                          ),
                          Text(
                            '手动记录',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: tokens.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
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

class _FlowDateControl extends StatelessWidget {
  const _FlowDateControl({
    required this.day,
    required this.today,
    required this.selected,
    required this.itemCount,
    required this.flashCount,
    required this.onTap,
    required this.onOpenFlash,
  });

  final DateTime day;
  final DateTime today;
  final bool selected;
  final int itemCount;
  final int flashCount;
  final VoidCallback onTap;
  final VoidCallback onOpenFlash;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final isToday = calendarDayKey(day) == calendarDayKey(today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '${day.month}月${day.day}日，$itemCount 项',
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
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: isToday || selected
                                ? tokens.accent
                                : tokens.foreground,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                    ),
                    Text(
                      _weekday(day),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (flashCount > 0)
          Semantics(
            label: '${day.month}月${day.day}日，$flashCount 条闪念，查看闪念',
            button: true,
            onTap: onOpenFlash,
            child: ExcludeSemantics(
              child: InkWell(
                key: ValueKey('calendar-flash-${calendarDayKey(day)}'),
                onTap: onOpenFlash,
                borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                child: Container(
                  margin: const EdgeInsets.only(top: ThemeV2Spacing.sm),
                  width: 44,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    border: Border.all(color: tokens.accent),
                  ),
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
      ],
    );
  }

  static String _weekday(DateTime day) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];
}
