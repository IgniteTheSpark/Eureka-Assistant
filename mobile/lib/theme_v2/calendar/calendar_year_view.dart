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

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      key: const ValueKey('calendar-year-view'),
      color: tokens.background,
      padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CALENDAR / YEAR',
                      style: ThemeV2Typography.mono(
                        fontSize: 8,
                        color: tokens.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
              ThemeV2IconButton(
                semanticLabel: '下一年',
                icon: Icons.chevron_right,
                onPressed: () => setState(() => _year++),
                color: tokens.muted,
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = ThemeV2Spacing.md;
                final width = (constraints.maxWidth - gap * 2) / 3;
                final height = (constraints.maxHeight * 0.63 / 4).clamp(
                  76.0,
                  112.0,
                );
                return GridView.builder(
                  key: const ValueKey('calendar-year-grid'),
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    childAspectRatio: width / height,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    final count = widget.data.byDay.entries
                        .where(
                          (entry) =>
                              entry.key.year == _year &&
                              entry.key.month == month,
                        )
                        .fold<int>(0, (sum, entry) => sum + entry.value.length);
                    return _YearMonthCell(
                      year: _year,
                      month: month,
                      count: count,
                      selected: month == _selectedMonth,
                      onTap: () {
                        setState(() => _selectedMonth = month);
                        widget.onSelectMonth(DateTime(_year, month));
                      },
                    );
                  },
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
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int year;
  final int month;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '$year年$month月，$count 项',
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
              padding: const EdgeInsets.all(ThemeV2Spacing.md),
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
                  Text(
                    '$count 项',
                    style: ThemeV2Typography.mono(
                      fontSize: 9,
                      color: selected ? tokens.accent : tokens.muted,
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
