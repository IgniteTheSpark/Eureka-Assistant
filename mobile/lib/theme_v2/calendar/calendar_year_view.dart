import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'calendar_models.dart';

class CalendarYearView extends StatefulWidget {
  const CalendarYearView({
    super.key,
    required this.focusMonth,
    required this.data,
    required this.today,
    required this.onSelectMonth,
  });

  final DateTime focusMonth;
  final CalendarData data;
  final DateTime today;
  final ValueChanged<DateTime> onSelectMonth;

  @override
  State<CalendarYearView> createState() => _CalendarYearViewState();
}

class _CalendarYearViewState extends State<CalendarYearView> {
  late int _year = widget.focusMonth.year;
  late int _selectedMonth = widget.focusMonth.month;

  @override
  void didUpdateWidget(CalendarYearView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusMonth.year != widget.focusMonth.year ||
        oldWidget.focusMonth.month != widget.focusMonth.month) {
      _year = widget.focusMonth.year;
      _selectedMonth = widget.focusMonth.month;
    }
  }

  List<CalendarRecord> _recordsFor(int month) => widget.data.records
      .where(
        (record) =>
            record.item.kind != 'input_turn' &&
            record.effectiveAt.year == _year &&
            record.effectiveAt.month == month,
      )
      .toList(growable: false);

  int _flashesFor(int month) => widget.data.items
      .where(
        (item) =>
            item.kind == 'input_turn' &&
            item.effectiveAt.year == _year &&
            item.effectiveAt.month == month,
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final monthCounts = [
      for (var month = 1; month <= 12; month++) _recordsFor(month).length,
    ];
    final maxCount = monthCounts.fold<int>(
      1,
      (maximum, count) => count > maximum ? count : maximum,
    );
    final selectedRecords = _recordsFor(_selectedMonth);
    final selectedFlashes = _flashesFor(_selectedMonth);
    return Container(
      key: const ValueKey('calendar-year-view'),
      color: tokens.background,
      padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            key: ValueKey('calendar-year-top-gap'),
            height: ThemeV2Spacing.xs,
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_year',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              ThemeV2IconButton(
                semanticLabel: '上一年',
                icon: Icons.chevron_left,
                onPressed: () => setState(() => _year--),
                color: tokens.muted,
              ),
              Semantics(
                label: '回到今年',
                button: true,
                onTap: () => setState(() {
                  _year = widget.today.year;
                  _selectedMonth = widget.today.month;
                }),
                child: ExcludeSemantics(
                  child: ThemeV2HitTarget(
                    child: InkWell(
                      onTap: () => setState(() {
                        _year = widget.today.year;
                        _selectedMonth = widget.today.month;
                      }),
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
                semanticLabel: '下一年',
                icon: Icons.chevron_right,
                onPressed: () => setState(() => _year++),
                color: tokens.muted,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: ThemeV2Spacing.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = ThemeV2Spacing.md;
                final width = (constraints.maxWidth - gap * 2) / 3;
                final gridHeight = (constraints.maxHeight - 212)
                    .clamp(260.0, 452.0)
                    .toDouble();
                final cellHeight = (gridHeight - gap * 3) / 4;
                return Column(
                  children: [
                    SizedBox(
                      height: gridHeight,
                      child: GridView.builder(
                        key: const ValueKey('calendar-year-grid'),
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: gap,
                          mainAxisSpacing: gap,
                          childAspectRatio: width / cellHeight,
                        ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final month = index + 1;
                          final count = monthCounts[index];
                          return _YearMonthCell(
                            year: _year,
                            month: month,
                            recordCount: count,
                            flashCount: _flashesFor(month),
                            activity: count / maxCount,
                            selected: month == _selectedMonth,
                            onTap: () {
                              setState(() => _selectedMonth = month);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: ThemeV2Spacing.md),
                    _YearOverview(
                      year: _year,
                      month: _selectedMonth,
                      records: selectedRecords,
                      flashCount: selectedFlashes,
                      onOpenMonth: () =>
                          widget.onSelectMonth(DateTime(_year, _selectedMonth)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _YearMonthCell extends StatelessWidget {
  const _YearMonthCell({
    required this.year,
    required this.month,
    required this.recordCount,
    required this.flashCount,
    required this.activity,
    required this.selected,
    required this.onTap,
  });

  final int year;
  final int month;
  final int recordCount;
  final int flashCount;
  final double activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '$year年$month月，$recordCount 条记录，$flashCount 条闪念',
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: InkWell(
            key: ValueKey('calendar-year-$year-$month'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? tokens.accentSoft : tokens.surface,
                borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                border: Border.all(
                  color: selected ? tokens.accent : tokens.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$month月',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        '$recordCount 条',
                        style: ThemeV2Typography.mono(
                          fontSize: 14,
                          color: tokens.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (flashCount > 0)
                        Text(
                          '⚡ $flashCount',
                          style: ThemeV2Typography.mono(
                            fontSize: 8,
                            color: tokens.muted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    child: LinearProgressIndicator(
                      value: activity,
                      minHeight: 4,
                      backgroundColor: tokens.border,
                      valueColor: AlwaysStoppedAnimation(
                        selected ? tokens.accent : tokens.muted,
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

class _YearOverview extends StatelessWidget {
  const _YearOverview({
    required this.year,
    required this.month,
    required this.records,
    required this.flashCount,
    required this.onOpenMonth,
  });

  final int year;
  final int month;
  final List<CalendarRecord> records;
  final int flashCount;
  final VoidCallback onOpenMonth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final eventCount = records.where((record) => record.isEvent).length;
    return Container(
      key: const ValueKey('calendar-year-summary'),
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeV2Spacing.lg),
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
                '$month月概览',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: ThemeV2Sizes.minTouchTarget,
                child: OutlinedButton(
                  onPressed: onOpenMonth,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.accent,
                    side: BorderSide(color: tokens.accent),
                  ),
                  child: const Text('查看月度 ›'),
                ),
              ),
            ],
          ),
          Text(
            '$year · 已选择',
            style: ThemeV2Typography.mono(fontSize: 8, color: tokens.muted),
          ),
          const SizedBox(height: ThemeV2Spacing.md),
          Row(
            children: [
              Expanded(
                child: _OverviewStat(
                  key: const ValueKey('calendar-year-summary-records'),
                  label: '记录',
                  value: '${records.length} 条',
                ),
              ),
              const SizedBox(width: ThemeV2Spacing.sm),
              Expanded(
                child: _OverviewStat(label: '日程', value: '$eventCount 个'),
              ),
              const SizedBox(width: ThemeV2Spacing.sm),
              Expanded(
                child: _OverviewStat(label: '闪念', value: '$flashCount 条'),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '月度节奏',
            style: ThemeV2Typography.mono(
              fontSize: 8,
              color: tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          Row(
            children: [
              for (final fraction in const [1.0, 0.78, 0.54, 0.88, 0.66]) ...[
                Expanded(
                  flex: (fraction * 100).round(),
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: fraction),
                      borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    ),
                  ),
                ),
                const SizedBox(width: ThemeV2Spacing.xs),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      padding: const EdgeInsets.all(ThemeV2Spacing.md),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: ThemeV2Typography.mono(fontSize: 8, color: tokens.muted),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: tokens.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
