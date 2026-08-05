import 'package:flutter/material.dart';

import '../../render/render_spec.dart';
import '../../timeline/timeline.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'calendar_components.dart';
import 'calendar_controller.dart';
import 'calendar_inline_draft.dart';
import 'calendar_models.dart';
import 'calendar_time_layout.dart';

class CalendarScheduleGrid extends StatefulWidget {
  const CalendarScheduleGrid({
    super.key,
    required this.day,
    required this.records,
    required this.skills,
    required this.controller,
    required this.onOpenRecord,
    this.onToggleTodo,
    required this.onCreateDraft,
    required this.onOpenDraftEditor,
  });

  final DateTime day;
  final List<CalendarRecord> records;
  final Map<String, SkillMeta> skills;
  final CalendarController controller;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final Future<void> Function(CalendarRecord)? onToggleTodo;
  final CalendarDraftMutation onCreateDraft;
  final ValueChanged<CalendarInlineDraft> onOpenDraftEditor;

  @override
  State<CalendarScheduleGrid> createState() => _CalendarScheduleGridState();
}

class _CalendarScheduleGridState extends State<CalendarScheduleGrid> {
  static const _startHour = 0;
  static const _endHour = 24;
  static const _hourHeight = 88.0;
  static const _halfHourHeight = _hourHeight / 2;
  static const _timeWidth = 54.0;
  static const _columnGap = 4.0;
  static const _expandedRowHeight = 44.0;
  // 15 minutes at 64 logical pixels per hour.
  static const _collapsedBandHeight = _hourHeight / 4;
  final Set<DateTime> _expandedBands = {};
  CalendarInlineDraft? _displayedDraft;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: 8 * _hourHeight,
  );

  bool _sameDay(DateTime time) =>
      time.year == widget.day.year &&
      time.month == widget.day.month &&
      time.day == widget.day.day;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dayRecords = widget.records.where(
      (record) =>
          _sameDay(record.effectiveAt) && (record.isEvent || record.isTodo),
    );
    final timed = dayRecords.where((record) => record.isTimed).toList();
    final untimed = dayRecords
        .where(
          (record) =>
              record.isTodo && record.timing == CalendarRecordTiming.untimed,
        )
        .toList();
    final allDay = dayRecords
        .where((record) => record.timing == CalendarRecordTiming.allDay)
        .toList();
    final bands = buildCalendarTodoBands(timed);
    final bandById = <String, CalendarTodoBand>{
      for (final band in bands)
        for (final todo in band.todos) todo.id: band,
    };
    final layoutRecords = <CalendarRecord>[
      for (final record in timed)
        if (bandById[record.id] == null ||
            bandById[record.id]!.todos.first.id == record.id)
          record,
    ];
    final layout = layoutCalendarTime(
      layoutRecords,
      endMinuteOverrides: {
        for (final band in bands)
          band.todos.first.id:
              _minuteOfDay(band.startAt) + band.collapsedDuration.inMinutes,
      },
    );
    final expansions = <(int, double)>[
      for (final band in bands)
        if (_expandedBands.contains(band.startAt))
          (
            _minuteOfDay(band.startAt),
            ThemeV2Sizes.minTouchTarget -
                _collapsedBandHeight +
                band.todos.length * _expandedRowHeight,
          ),
    ];
    final baseHeight = (_endHour - _startHour) * _hourHeight;
    final totalHeight =
        baseHeight +
        expansions.fold<double>(0, (sum, expansion) => sum + expansion.$2);
    final activeDraft = widget.controller.inlineDraft;
    if (activeDraft != null) _displayedDraft = activeDraft;

    return ColoredBox(
      color: context.themeV2.background,
      child: Column(
        children: [
          if (allDay.isNotEmpty || untimed.isNotEmpty)
            _TopTrays(
              allDay: allDay,
              untimed: untimed,
              onOpenRecord: widget.onOpenRecord,
              onToggleTodo: widget.onToggleTodo,
            ),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('calendar-schedule-scroll'),
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 96),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = (constraints.maxWidth - _timeWidth).clamp(
                    80.0,
                    double.infinity,
                  );
                  return SizedBox(
                    height: totalHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var hour = _startHour; hour < _endHour; hour++)
                          for (final minute in const [0, 30])
                            _TimeSlot(
                              startAt: DateTime(
                                widget.day.year,
                                widget.day.month,
                                widget.day.day,
                                hour,
                                minute,
                              ),
                              top:
                                  _topForMinute(hour * 60 + minute) +
                                  _pushAt(hour * 60 + minute, expansions),
                              height: _halfHourHeight,
                              isHourBoundary: minute == 0,
                              onTap: () => _createAt(
                                DateTime(
                                  widget.day.year,
                                  widget.day.month,
                                  widget.day.day,
                                  hour,
                                  minute,
                                ),
                              ),
                            ),
                        for (final entry in layout)
                          if (bandById[entry.id] case final band?)
                            _TodoBandBlock(
                              band: band,
                              expanded: _expandedBands.contains(band.startAt),
                              top:
                                  _topForMinute(entry.startMinute) +
                                  _pushAt(entry.startMinute, expansions),
                              left:
                                  _timeWidth +
                                  entry.columnIndex *
                                      ((available -
                                                  _columnGap *
                                                      (entry.columnCount - 1)) /
                                              entry.columnCount +
                                          _columnGap),
                              width:
                                  (available -
                                      _columnGap * (entry.columnCount - 1)) /
                                  entry.columnCount,
                              expandedRowHeight: _expandedRowHeight,
                              collapsedHeight: _collapsedBandHeight,
                              onToggle: () => setState(() {
                                if (!_expandedBands.add(band.startAt)) {
                                  _expandedBands.remove(band.startAt);
                                }
                              }),
                              onOpenRecord: widget.onOpenRecord,
                              onToggleTodo: widget.onToggleTodo,
                            )
                          else
                            _TimedRecordBlock(
                              entry: entry,
                              top:
                                  _topForMinute(entry.startMinute) +
                                  _pushAt(entry.startMinute, expansions),
                              left:
                                  _timeWidth +
                                  entry.columnIndex *
                                      ((available -
                                                  _columnGap *
                                                      (entry.columnCount - 1)) /
                                              entry.columnCount +
                                          _columnGap),
                              width:
                                  (available -
                                      _columnGap * (entry.columnCount - 1)) /
                                  entry.columnCount,
                              height:
                                  (entry.endMinute - entry.startMinute) /
                                  60 *
                                  _hourHeight,
                              onTap: () => widget.onOpenRecord(entry.record),
                              onToggleTodo: widget.onToggleTodo == null
                                  ? null
                                  : () => widget.onToggleTodo!(entry.record),
                            ),
                        if (_displayedDraft case final draft?)
                          Positioned(
                            top:
                                _topForMinute(_minuteOfDay(draft.startAt)) +
                                _pushAt(
                                  _minuteOfDay(draft.startAt),
                                  expansions,
                                ),
                            left: _timeWidth,
                            width: available,
                            child: CalendarInlineDraftView(
                              key: ValueKey(
                                'calendar-inline-${draft.startAt.toIso8601String()}',
                              ),
                              controller: widget.controller,
                              onCreate: widget.onCreateDraft,
                              onOpenEditor: widget.onOpenDraftEditor,
                              onChanged: () => setState(() {}),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _createAt(DateTime start) {
    widget.controller.tapEmptyTime(start);
    setState(() => _displayedDraft = widget.controller.inlineDraft);
  }

  double _topForMinute(int minute) =>
      (minute - _startHour * 60) / 60 * _hourHeight;

  double _pushAt(int minute, List<(int, double)> expansions) {
    var push = 0.0;
    for (final expansion in expansions) {
      if (expansion.$1 < minute) push += expansion.$2;
    }
    return push;
  }

  int _minuteOfDay(DateTime time) => time.hour * 60 + time.minute;
}

class _TimeSlot extends StatelessWidget {
  const _TimeSlot({
    required this.startAt,
    required this.top,
    required this.height,
    required this.isHourBoundary,
    required this.onTap,
  });

  final DateTime startAt;
  final double top;
  final double height;
  final bool isHourBoundary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final label =
        '${startAt.hour.toString().padLeft(2, '0')}:'
        '${startAt.minute.toString().padLeft(2, '0')}';
    final key =
        'calendar-empty-slot-${calendarDayKey(startAt)}-'
        '${startAt.hour.toString().padLeft(2, '0')}'
        '${startAt.minute.toString().padLeft(2, '0')}';
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      height: height,
      child: Semantics(
        label: '$label 空白时间，创建日程',
        button: true,
        onTap: onTap,
        child: ExcludeSemantics(
          child: GestureDetector(
            key: ValueKey(key),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isHourBoundary
                        ? tokens.border
                        : tokens.border.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: ThemeV2Spacing.xs),
                child: Text(
                  label,
                  style: ThemeV2Typography.mono(
                    fontSize: isHourBoundary ? 9 : 8,
                    color: tokens.muted.withValues(
                      alpha: isHourBoundary ? 1 : 0.68,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimedRecordBlock extends StatelessWidget {
  const _TimedRecordBlock({
    required this.entry,
    required this.top,
    required this.left,
    required this.width,
    required this.height,
    required this.onTap,
    required this.onToggleTodo,
  });

  final CalendarTimeLayoutEntry entry;
  final double top;
  final double left;
  final double width;
  final double height;
  final VoidCallback onTap;
  final Future<void> Function()? onToggleTodo;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final visualHeight = height.clamp(1.0, double.infinity);
    final hitHeight = visualHeight.clamp(
      ThemeV2Sizes.minTouchTarget,
      double.infinity,
    );
    final block = Align(
      alignment: Alignment.topCenter,
      child: Container(
        key: ValueKey('calendar-grid-record-${entry.id}'),
        width: double.infinity,
        height: visualHeight,
        padding: EdgeInsets.symmetric(
          horizontal: entry.record.isTodo ? 2 : ThemeV2Spacing.sm,
          vertical: entry.record.isTodo
              ? 0
              : visualHeight >= ThemeV2Sizes.minTouchTarget
              ? ThemeV2Spacing.xs
              : 1,
        ),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
          border: Border.all(color: tokens.accent),
        ),
        child: entry.record.isTodo
            ? _ScheduleTodoRow(
                record: entry.record,
                compact: true,
                onOpen: onTap,
                onToggle: onToggleTodo,
              )
            : InkWell(
                onTap: onTap,
                child: _ScheduleEventLabel(
                  entry: entry,
                  compact: visualHeight < 32,
                ),
              ),
      ),
    );
    return Positioned(
      top: top,
      left: left,
      width: width,
      height: hitHeight,
      child: entry.record.isTodo
          ? block
          : Semantics(
              label: entry.record.item.title,
              button: true,
              onTap: onTap,
              child: ExcludeSemantics(child: block),
            ),
    );
  }
}

class _ScheduleEventLabel extends StatelessWidget {
  const _ScheduleEventLabel({required this.entry, required this.compact});

  final CalendarTimeLayoutEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final range = _scheduleEventRange(entry);
    final titleStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tokens.foreground,
      fontWeight: FontWeight.w700,
    );
    if (compact) {
      return Text(
        '$range  ${entry.record.item.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ThemeV2Typography.mono(
          fontSize: 8,
          color: tokens.foreground,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          range,
          maxLines: 1,
          style: ThemeV2Typography.mono(
            fontSize: 8,
            color: tokens.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text(
            entry.record.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
      ],
    );
  }
}

String _scheduleEventRange(CalendarTimeLayoutEntry entry) {
  final start = entry.record.effectiveAt;
  final declaredEnd = entry.record.endAt;
  final end = declaredEnd != null && declaredEnd.isAfter(start)
      ? declaredEnd
      : start.add(entry.duration);
  return '${_scheduleClock(start)}–${_scheduleClock(end)}';
}

class _TodoBandBlock extends StatelessWidget {
  const _TodoBandBlock({
    required this.band,
    required this.expanded,
    required this.top,
    required this.left,
    required this.width,
    required this.expandedRowHeight,
    required this.collapsedHeight,
    required this.onToggle,
    required this.onOpenRecord,
    required this.onToggleTodo,
  });

  final CalendarTodoBand band;
  final bool expanded;
  final double top;
  final double left;
  final double width;
  final double expandedRowHeight;
  final double collapsedHeight;
  final VoidCallback onToggle;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final Future<void> Function(CalendarRecord)? onToggleTodo;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Positioned(
      top: expanded
          ? top
          : top - (ThemeV2Sizes.minTouchTarget - collapsedHeight),
      left: left,
      width: width,
      height: expanded
          ? ThemeV2Sizes.minTouchTarget + band.todos.length * expandedRowHeight
          : ThemeV2Sizes.minTouchTarget,
      child: OverflowBox(
        // Grow the collapsed hit target upward from the true 15-minute band,
        // keeping later scheduled records' hit regions unambiguous.
        alignment: expanded ? Alignment.topCenter : Alignment.bottomCenter,
        minHeight: ThemeV2Sizes.minTouchTarget,
        maxHeight: expanded
            ? ThemeV2Sizes.minTouchTarget +
                  band.todos.length * expandedRowHeight
            : ThemeV2Sizes.minTouchTarget,
        child: Container(
          decoration: BoxDecoration(
            color: expanded ? tokens.accentSoft : null,
            gradient: expanded
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      tokens.accentSoft,
                      tokens.accentSoft,
                    ],
                    stops: [
                      0,
                      1 - collapsedHeight / ThemeV2Sizes.minTouchTarget,
                      1 - collapsedHeight / ThemeV2Sizes.minTouchTarget,
                      1,
                    ],
                  ),
            borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
          ),
          child: Column(
            children: [
              Semantics(
                key: ValueKey(
                  'calendar-grid-todo-band-${calendarDayKey(band.startAt)}-'
                  '${band.startAt.hour.toString().padLeft(2, '0')}'
                  '${band.startAt.minute.toString().padLeft(2, '0')}',
                ),
                label: '${expanded ? '收起' : '展开'} ${band.todos.length} 个待办',
                button: true,
                onTap: onToggle,
                child: ExcludeSemantics(
                  child: ThemeV2HitTarget(
                    child: InkWell(
                      onTap: onToggle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ThemeV2Spacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${band.todos.length} 个待办',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: tokens.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            Icon(
                              expanded ? Icons.expand_less : Icons.expand_more,
                              size: 16,
                              color: tokens.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (expanded)
                for (final todo in band.todos)
                  SizedBox(
                    height: expandedRowHeight,
                    child: _ScheduleTodoRow(
                      record: todo,
                      onOpen: () => onOpenRecord(todo),
                      onToggle: onToggleTodo == null
                          ? null
                          : () => onToggleTodo!(todo),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopTrays extends StatelessWidget {
  const _TopTrays({
    required this.allDay,
    required this.untimed,
    required this.onOpenRecord,
    required this.onToggleTodo,
  });

  final List<CalendarRecord> allDay;
  final List<CalendarRecord> untimed;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final Future<void> Function(CalendarRecord)? onToggleTodo;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.sm),
      child: Column(
        children: [
          if (allDay.isNotEmpty) ...[
            Container(
              key: const ValueKey('calendar-all-day-tray'),
              height: 54,
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.md,
                vertical: ThemeV2Spacing.xs,
              ),
              decoration: _trayDecoration(tokens),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TrayLabel('全天日程 · ${allDay.length}'),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: allDay.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: ThemeV2Spacing.lg),
                      itemBuilder: (context, index) {
                        final record = allDay[index];
                        return InkWell(
                          onTap: () => onOpenRecord(record),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '📅 ${record.item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: tokens.foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
          ],
          if (untimed.isNotEmpty)
            Container(
              key: const ValueKey('calendar-unscheduled-tray'),
              height: 92,
              padding: const EdgeInsets.fromLTRB(
                ThemeV2Spacing.md,
                ThemeV2Spacing.xs,
                ThemeV2Spacing.sm,
                ThemeV2Spacing.xs,
              ),
              decoration: _trayDecoration(tokens),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TrayLabel('未排期待办 · ${untimed.length}'),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('calendar-unscheduled-scroll'),
                      primary: false,
                      padding: EdgeInsets.zero,
                      physics: untimed.length > 3
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: untimed.length,
                      itemExtent: 24,
                      itemBuilder: (context, index) {
                        final record = untimed[index];
                        return _ScheduleTodoRow(
                          record: record,
                          compact: true,
                          onOpen: () => onOpenRecord(record),
                          onToggle: onToggleTodo == null
                              ? null
                              : () => onToggleTodo!(record),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration _trayDecoration(ThemeV2Tokens tokens) => BoxDecoration(
    color: tokens.surface,
    borderRadius: BorderRadius.circular(ThemeV2Radii.md),
    border: Border.all(color: tokens.border),
  );
}

class _TrayLabel extends StatelessWidget {
  const _TrayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: ThemeV2Typography.mono(
        fontSize: 9,
        color: context.themeV2.muted,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ScheduleTodoRow extends StatelessWidget {
  const _ScheduleTodoRow({
    required this.record,
    required this.onOpen,
    required this.onToggle,
    this.compact = false,
  });

  final CalendarRecord record;
  final VoidCallback onOpen;
  final Future<void> Function()? onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final done = todoPayloadIsDone(record.item.payload);
    return Row(
      children: [
        Semantics(
          label: '${done ? '取消完成' : '完成'}待办：${record.item.title}',
          button: true,
          checked: done,
          onTap: onToggle,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onToggle,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: compact ? 24 : ThemeV2Sizes.minTouchTarget,
                height: compact ? 24 : ThemeV2Sizes.minTouchTarget,
                child: Icon(
                  done ? Icons.check_box : Icons.check_box_outline_blank,
                  size: compact ? 17 : 19,
                  color: done ? tokens.accent : tokens.muted,
                ),
              ),
            ),
          ),
        ),
        if (record.isTimed) ...[
          Text(
            _scheduleClock(record.effectiveAt),
            style: ThemeV2Typography.mono(
              fontSize: compact ? 8 : 9,
              color: tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: ThemeV2Spacing.xs),
        ],
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                record.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: done ? tokens.muted : tokens.foreground,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _scheduleClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
