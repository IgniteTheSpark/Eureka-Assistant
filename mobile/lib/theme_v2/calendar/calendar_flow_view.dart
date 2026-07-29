import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../timeline/timeline.dart';
import '../foundation/theme_v2_motion.dart';
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
  static const _dayCount = _pastDays + _futureDays + 1;
  static const _emptyDayExtent = 150.0;
  static const _minimumDayExtent = 180.0;

  late List<double> _dayExtents;
  late List<double> _dayOffsets;
  late final ScrollController _scroll;
  late final ValueNotifier<int> _leadingIndex;
  late final ValueNotifier<_FlowViewportState> _viewportState;
  DateTime? _manualConfirmationDay;
  double _lastScrollOffset = 0;
  int _scrollDirection = 1;
  _FlowScrollPhase _phase = _FlowScrollPhase.idle;
  int _returnGeneration = 0;

  DateTime get _firstDay =>
      calendarDayOf(widget.today).subtract(const Duration(days: _pastDays));

  DateTime _dayAt(int index) => _firstDay.add(Duration(days: index));

  @override
  void initState() {
    super.initState();
    _rebuildMetrics();
    final initialOffset = _dayOffsets[_pastDays];
    _lastScrollOffset = initialOffset;
    _leadingIndex = ValueNotifier<int>(_pastDays);
    _viewportState = ValueNotifier<_FlowViewportState>(
      _viewportFor(
        initialOffset,
        viewportDimension: 0,
        phase: _FlowScrollPhase.idle,
      ),
    );
    _scroll = ScrollController(initialScrollOffset: initialOffset)
      ..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncViewportState();
    });
  }

  double _dayExtent(int index) => _dayExtents[index];

  double _dayExtentFor(CalendarData data, int index) {
    final items =
        data.byDay[calendarDayOf(_dayAt(index))] ?? const <TimelineItem>[];
    var assetCount = 0;
    var untimedCount = 0;
    final bands = <_FlowBand>{};
    for (final item in items) {
      if (item.kind == 'input_turn') continue;
      final record = CalendarRecord.fromTimeline(item);
      assetCount++;
      if (!record.isTimed) untimedCount++;
      bands.add(_flowBandFor(record));
    }
    if (assetCount == 0) return _emptyDayExtent;
    return math.max(
      _minimumDayExtent,
      128 + assetCount * 44 + bands.length * 28 + untimedCount * 20,
    );
  }

  void _rebuildMetrics() {
    _dayExtents = List<double>.generate(
      _dayCount,
      (index) => _dayExtentFor(widget.data, index),
      growable: false,
    );
    _dayOffsets = List<double>.filled(_dayCount + 1, 0);
    for (var index = 0; index < _dayCount; index++) {
      _dayOffsets[index + 1] = _dayOffsets[index] + _dayExtents[index];
    }
  }

  void _onScroll() {
    final offset = _scroll.offset;
    if ((offset - _lastScrollOffset).abs() > 0.01) {
      _scrollDirection = offset > _lastScrollOffset ? 1 : -1;
      _lastScrollOffset = offset;
    }
    _syncViewportState();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        if (_phase == _FlowScrollPhase.returningToToday) {
          _returnGeneration++;
        }
        _phase = _FlowScrollPhase.dragging;
      } else if (_phase != _FlowScrollPhase.returningToToday) {
        _phase = _FlowScrollPhase.decelerating;
      }
      _syncViewportState();
    } else if (notification is ScrollEndNotification) {
      _phase = _FlowScrollPhase.idle;
      _syncViewportState();
    }
    return false;
  }

  void _syncViewportState() {
    if (!_scroll.hasClients) return;
    final next = _viewportFor(
      _scroll.offset,
      viewportDimension: _scroll.position.viewportDimension,
      phase: _phase,
    );
    if (_leadingIndex.value != next.leadingIndex) {
      _leadingIndex.value = next.leadingIndex;
    }
    if (_viewportState.value != next) _viewportState.value = next;
  }

  _FlowViewportState _viewportFor(
    double offset, {
    required double viewportDimension,
    required _FlowScrollPhase phase,
  }) {
    final leadingIndex = _indexAt(offset);
    final remaining = _dayOffsets[leadingIndex + 1] - offset;
    final railPushOffset = remaining < 136 ? remaining - 136 : 0.0;
    final centerIndex = _centerIndexAt(
      offset,
      viewportDimension,
      _scrollDirection,
    );
    final centerDay = _dayAt(centerIndex);
    final dayDistance = calendarDayOf(
      centerDay,
    ).difference(calendarDayOf(widget.today)).inDays;
    return _FlowViewportState(
      leadingIndex: leadingIndex,
      centerDay: centerDay,
      railPushOffset: railPushOffset,
      watermark: calendarDistanceLabel(centerDay, widget.today),
      showWatermark: phase != _FlowScrollPhase.idle,
      showReturnToday: dayDistance.abs() >= 7,
      phase: phase,
    );
  }

  int _indexAt(double position) {
    final target = position.clamp(0.0, _dayOffsets.last);
    var low = 0;
    var high = _dayCount;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_dayOffsets[middle + 1] <= target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low.clamp(0, _dayCount - 1);
  }

  int _centerIndexAt(
    double scrollOffset,
    double viewportDimension,
    int direction,
  ) {
    final center = scrollOffset + viewportDimension / 2;
    final rightIndex = _indexAt(center);
    if (rightIndex == 0 || (center - _dayOffsets[rightIndex]).abs() > 0.01) {
      return rightIndex;
    }

    final leftIndex = rightIndex - 1;
    final viewportEnd = scrollOffset + viewportDimension;
    double visibleArea(int index) =>
        (math.min(_dayOffsets[index + 1], viewportEnd) -
                math.max(_dayOffsets[index], scrollOffset))
            .clamp(0.0, double.infinity);
    final leftArea = visibleArea(leftIndex);
    final rightArea = visibleArea(rightIndex);
    if ((leftArea - rightArea).abs() <= 0.01) {
      return direction < 0 ? leftIndex : rightIndex;
    }
    return leftArea > rightArea ? leftIndex : rightIndex;
  }

  Future<void> _returnToToday() async {
    if (!_scroll.hasClients || _phase == _FlowScrollPhase.returningToToday) {
      return;
    }
    final generation = ++_returnGeneration;
    _phase = _FlowScrollPhase.returningToToday;
    _syncViewportState();
    final viewport = _scroll.position.viewportDimension;
    final target =
        (_dayOffsets[_pastDays] + _dayExtents[_pastDays] / 2 - viewport / 2)
            .clamp(
              _scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent,
            );
    final duration = ThemeV2Motion.duration(context, ThemeV2MotionToken.fluid);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      await _scroll.animateTo(
        target,
        duration: duration,
        curve: ThemeV2Motion.easeFluid,
      );
    }
    if (!mounted || generation != _returnGeneration) return;
    _phase = _FlowScrollPhase.idle;
    _syncViewportState();
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
    _leadingIndex.dispose();
    _viewportState.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CalendarFlowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data) ||
        calendarDayOf(oldWidget.today) != calendarDayOf(widget.today)) {
      final todayChanged =
          calendarDayOf(oldWidget.today) != calendarDayOf(widget.today);
      final oldLeading = _leadingIndex.value;
      final oldTop = _dayOffsets[oldLeading];
      final intraDayOffset = _scroll.hasClients ? _scroll.offset - oldTop : 0.0;
      _rebuildMetrics();
      final nextLeading = todayChanged ? _pastDays : oldLeading;
      _leadingIndex.value = nextLeading;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target =
            (_dayOffsets[nextLeading] + (todayChanged ? 0.0 : intraDayOffset))
                .clamp(
                  _scroll.position.minScrollExtent,
                  _scroll.position.maxScrollExtent,
                );
        if ((_scroll.offset - target).abs() > 0.5) {
          _scroll.jumpTo(target);
        }
        _syncViewportState();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(
            key: const ValueKey('calendar-flow-content'),
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: ListView.builder(
                key: const ValueKey('calendar-flow-scroll'),
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: _dayCount,
                itemExtentBuilder: (index, _) => _dayExtents[index],
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
                      dayIndex: index,
                      leadingIndex: _leadingIndex,
                      day: day,
                      today: widget.today,
                      items: items,
                      skills: widget.data.skills,
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
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<_FlowViewportState>(
              valueListenable: _viewportState,
              builder: (context, state, _) {
                return Align(
                  alignment: const Alignment(0, -0.08),
                  child: AnimatedSwitcher(
                    duration: ThemeV2Motion.duration(
                      context,
                      ThemeV2MotionToken.fast,
                    ),
                    child: state.showWatermark
                        ? Text(
                            state.watermark,
                            key: const ValueKey('calendar-flow-watermark'),
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(
                                  color: context.themeV2.watermark,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('calendar-flow-watermark-idle'),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: ValueListenableBuilder<_FlowViewportState>(
            valueListenable: _viewportState,
            builder: (context, state, _) {
              final visibleDay = _dayAt(state.leadingIndex);
              final items =
                  widget.data.byDay[calendarDayOf(visibleDay)] ??
                  const <TimelineItem>[];
              final assetCount = items
                  .where((item) => item.kind != 'input_turn')
                  .length;
              final flashCount = items.length - assetCount;
              return CalendarStickyDateRail(
                day: visibleDay,
                today: widget.today,
                itemCount: assetCount,
                flashCount: flashCount,
                pushOffset: state.railPushOffset,
                onTapDate: () => _activateDay(visibleDay),
                onOpenFlash: () => widget.onOpenFlash(visibleDay),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ValueListenableBuilder<_FlowViewportState>(
            valueListenable: _viewportState,
            builder: (context, state, _) {
              if (!state.showReturnToday) return const SizedBox.shrink();
              final enabled = state.phase != _FlowScrollPhase.returningToToday;
              final tokens = context.themeV2;
              return Center(
                child: Semantics(
                  label: '回到今天',
                  button: true,
                  enabled: enabled,
                  onTap: enabled ? _returnToToday : null,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 119,
                      height: 40,
                      child: Material(
                        color: tokens.surface.withValues(alpha: 0.95),
                        elevation: 6,
                        shadowColor: Colors.black.withValues(alpha: 0.14),
                        shape: StadiumBorder(
                          side: BorderSide(color: tokens.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: enabled ? _returnToToday : null,
                          child: Center(
                            child: Text(
                              '回到今天',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: tokens.foreground,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

enum _FlowScrollPhase { idle, dragging, decelerating, returningToToday }

class _FlowViewportState {
  const _FlowViewportState({
    required this.leadingIndex,
    required this.centerDay,
    required this.railPushOffset,
    required this.watermark,
    required this.showWatermark,
    required this.showReturnToday,
    required this.phase,
  });

  final int leadingIndex;
  final DateTime centerDay;
  final double railPushOffset;
  final String watermark;
  final bool showWatermark;
  final bool showReturnToday;
  final _FlowScrollPhase phase;

  @override
  bool operator ==(Object other) {
    return other is _FlowViewportState &&
        other.leadingIndex == leadingIndex &&
        other.centerDay == centerDay &&
        other.railPushOffset == railPushOffset &&
        other.watermark == watermark &&
        other.showWatermark == showWatermark &&
        other.showReturnToday == showReturnToday &&
        other.phase == phase;
  }

  @override
  int get hashCode => Object.hash(
    leadingIndex,
    centerDay,
    railPushOffset,
    watermark,
    showWatermark,
    showReturnToday,
    phase,
  );
}

class _FlowDateRailSlot extends StatelessWidget {
  const _FlowDateRailSlot({
    required this.dayIndex,
    required this.leadingIndex,
    required this.child,
  });

  final int dayIndex;
  final ValueListenable<int> leadingIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: leadingIndex,
      builder: (_, visibleIndex, _) {
        if (dayIndex == visibleIndex) return const SizedBox.shrink();
        return Positioned(
          left: ThemeV2Spacing.sm,
          top: ThemeV2Spacing.xs,
          child: child,
        );
      },
    );
  }
}

class _FlowDay extends StatelessWidget {
  const _FlowDay({
    required this.dayIndex,
    required this.leadingIndex,
    required this.day,
    required this.today,
    required this.items,
    required this.skills,
    required this.selected,
    required this.showManualConfirmation,
    required this.onActivateDay,
    required this.onRequestManualRecord,
    required this.onOpenRecord,
    required this.onOpenFlash,
  });

  final int dayIndex;
  final ValueListenable<int> leadingIndex;
  final DateTime day;
  final DateTime today;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
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
    final groups = _flowBandGroups(records);
    return RepaintBoundary(
      child: Stack(
        children: [
          _FlowDateRailSlot(
            dayIndex: dayIndex,
            leadingIndex: leadingIndex,
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
            bottom: records.isEmpty ? null : ThemeV2Spacing.lg,
            height: records.isEmpty ? _flowEmptyContentHeight : null,
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
                          : _EmptyDayHatch(day: day)
                    : ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        children: [
                          for (final group in groups)
                            _FlowBandSection(
                              group: group,
                              skills: skills,
                              onOpenRecord: onOpenRecord,
                            ),
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

enum _FlowBand { morning, afternoon, evening, untimed }

class _FlowBandGroup {
  const _FlowBandGroup({
    required this.band,
    required this.timed,
    required this.untimed,
  });

  final _FlowBand band;
  final List<CalendarRecord> timed;
  final List<CalendarRecord> untimed;

  int get count => timed.length + untimed.length;
}

List<_FlowBandGroup> _flowBandGroups(Iterable<CalendarRecord> records) {
  final timed = <_FlowBand, List<CalendarRecord>>{};
  final untimed = <_FlowBand, List<CalendarRecord>>{};
  for (final record in records) {
    final band = _flowBandFor(record);
    (record.isTimed ? timed : untimed)
        .putIfAbsent(band, () => <CalendarRecord>[])
        .add(record);
  }

  return [
    for (final band in _FlowBand.values)
      if ((timed[band]?.isNotEmpty ?? false) ||
          (untimed[band]?.isNotEmpty ?? false))
        _FlowBandGroup(
          band: band,
          timed: timed[band] ?? const <CalendarRecord>[],
          untimed: untimed[band] ?? const <CalendarRecord>[],
        ),
  ];
}

_FlowBand _flowBandFor(CalendarRecord record) {
  switch (record.period) {
    case '凌晨':
    case '上午':
    case '中午':
      return _FlowBand.morning;
    case '下午':
      return _FlowBand.afternoon;
    case '晚上':
      return _FlowBand.evening;
  }
  if (!record.isTimed) return _FlowBand.untimed;
  if (record.effectiveAt.hour < 12) return _FlowBand.morning;
  if (record.effectiveAt.hour < 18) return _FlowBand.afternoon;
  return _FlowBand.evening;
}

class _FlowBandSection extends StatelessWidget {
  const _FlowBandSection({
    required this.group,
    required this.skills,
    required this.onOpenRecord,
  });

  final _FlowBandGroup group;
  final Map<String, SkillMeta> skills;
  final ValueChanged<CalendarRecord> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final label = switch (group.band) {
      _FlowBand.morning => '上午',
      _FlowBand.afternoon => '下午',
      _FlowBand.evening => '晚上',
      _FlowBand.untimed => '没说时间',
    };
    return Padding(
      key: ValueKey('calendar-flow-band-${group.band.name}'),
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · ${group.count}',
            style: ThemeV2Typography.mono(
              fontSize: 9,
              color: tokens.accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          for (final record in group.timed)
            CalendarRecordRow(
              record: record,
              skills: skills,
              onTap: () => onOpenRecord(record),
            ),
          if (group.untimed.isNotEmpty && group.timed.isNotEmpty)
            CalendarUntimedDivider(recordId: group.untimed.first.id),
          for (final record in group.untimed)
            CalendarRecordRow(
              record: record,
              skills: skills,
              muted: true,
              onTap: () => onOpenRecord(record),
            ),
        ],
      ),
    );
  }
}

const _flowEmptyContentHeight = 58.0;

class _EmptyDayHatch extends StatelessWidget {
  const _EmptyDayHatch({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final brightness = Theme.of(context).brightness;
    return Container(
      key: ValueKey('calendar-empty-hatch-${calendarDayKey(day)}'),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.5),
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        key: ValueKey('calendar-empty-hatch-paint-${calendarDayKey(day)}'),
        painter: _DiagonalHatchPainter(
          tokens.muted.withValues(
            alpha: brightness == Brightness.dark ? 0.16 : 0.12,
          ),
        ),
      ),
    );
  }
}

class _DiagonalHatchPainter extends CustomPainter {
  const _DiagonalHatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const gap = 9.0;
    for (var x = 0.0; x < size.width + size.height; x += gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiagonalHatchPainter oldDelegate) =>
      oldDelegate.color != color;
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
          child: SizedBox(
            key: ValueKey(
              'calendar-empty-confirmation-card-${calendarDayKey(day)}',
            ),
            width: double.infinity,
            height: _flowEmptyContentHeight,
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
