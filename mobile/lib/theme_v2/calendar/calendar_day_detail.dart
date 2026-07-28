import 'package:flutter/material.dart';

import '../../timeline/timeline.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'calendar_components.dart';
import 'calendar_models.dart';

class CalendarDayDetail extends StatelessWidget {
  const CalendarDayDetail({
    super.key,
    required this.dayData,
    required this.skills,
    required this.onBack,
    required this.onOpenSchedule,
    required this.onOpenFlash,
    required this.onManualRecord,
    required this.onOpenRecord,
  });

  final CalendarDayData dayData;
  final Map<String, SkillMeta> skills;
  final VoidCallback onBack;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenFlash;
  final VoidCallback onManualRecord;
  final ValueChanged<CalendarRecord> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return ColoredBox(
      key: const ValueKey('calendar-day-detail'),
      color: tokens.background,
      child: ListView(
        key: ValueKey('calendar-day-detail-${calendarDayKey(dayData.day)}'),
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.lg,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.lg,
          112,
        ),
        children: [
          _DayHeader(
            dayData: dayData,
            onBack: onBack,
            onManualRecord: onManualRecord,
            onOpenSchedule: onOpenSchedule,
          ),
          _FlashEntry(dayData: dayData, onTap: onOpenFlash),
          const SizedBox(height: 20),
          if (dayData.assets.isEmpty)
            _AssetEmpty(onManualRecord: onManualRecord)
          else
            _DayBands(
              records: dayData.assets,
              skills: skills,
              onOpenRecord: onOpenRecord,
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.dayData,
    required this.onBack,
    required this.onManualRecord,
    required this.onOpenSchedule,
  });

  final CalendarDayData dayData;
  final VoidCallback onBack;
  final VoidCallback onManualRecord;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final day = dayData.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '返回日历',
          button: true,
          onTap: onBack,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${day.month}月 · ${_weekday(day)}',
                  style: ThemeV2Typography.mono(
                    fontSize: 10,
                    color: tokens.muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              day.day.toString().padLeft(2, '0'),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: tokens.foreground,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(width: ThemeV2Spacing.md),
            Text(
              '${dayData.assetCount} 项记录',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
            const Spacer(),
            _DayAction(
              semanticLabel: '${day.month}月${day.day}日，手动记录',
              icon: Icons.add,
              label: '手动记录',
              emphasized: true,
              onTap: onManualRecord,
            ),
            const SizedBox(width: ThemeV2Spacing.sm),
            _DayAction(
              semanticLabel: '${day.month}月${day.day}日，查看日程',
              icon: Icons.calendar_today_outlined,
              label: '日程',
              onTap: onOpenSchedule,
            ),
          ],
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
      ],
    );
  }

  static String _weekday(DateTime day) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];
}

class _DayAction extends StatelessWidget {
  const _DayAction({
    required this.semanticLabel,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final String semanticLabel;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: Material(
            color: emphasized ? tokens.accentSoft : tokens.surface,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeV2Spacing.md,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: emphasized ? tokens.accent : tokens.border,
                  ),
                  borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: emphasized ? tokens.accent : tokens.foreground,
                    ),
                    const SizedBox(width: ThemeV2Spacing.sm),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: emphasized ? tokens.accent : tokens.foreground,
                        fontWeight: FontWeight.w600,
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

class _FlashEntry extends StatelessWidget {
  const _FlashEntry({required this.dayData, required this.onTap});

  final CalendarDayData dayData;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final day = dayData.day;
    return Semantics(
      label: '${day.month}月${day.day}日，${dayData.flashCount} 条闪念，查看闪念',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: tokens.accentSoft,
          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          child: InkWell(
            key: ValueKey('calendar-day-flash-${calendarDayKey(dayData.day)}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(ThemeV2Radii.md),
            child: Container(
              height: ThemeV2Sizes.minTouchTarget,
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.md,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.accent),
                borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_outlined, size: 20, color: tokens.accent),
                  const SizedBox(width: ThemeV2Spacing.sm),
                  Text(
                    '闪念 ${dayData.flashCount}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 20, color: tokens.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetEmpty extends StatelessWidget {
  const _AssetEmpty({required this.onManualRecord});

  final VoidCallback onManualRecord;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      key: const ValueKey('calendar-day-asset-empty'),
      height: 420,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '今天还没有记录',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: ThemeV2Spacing.lg),
            Semantics(
              label: '手动记录',
              button: true,
              onTap: onManualRecord,
              child: ExcludeSemantics(
                child: ThemeV2HitTarget(
                  child: FilledButton.icon(
                    key: const ValueKey('calendar-day-empty-manual'),
                    onPressed: onManualRecord,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('手动记录'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(126, 44),
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
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
}

enum _DayBand { morning, afternoon, evening, untimed }

class _DayBands extends StatelessWidget {
  const _DayBands({
    required this.records,
    required this.skills,
    required this.onOpenRecord,
  });

  final List<CalendarRecord> records;
  final Map<String, SkillMeta> skills;
  final ValueChanged<CalendarRecord> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final groups = <_DayBand, List<CalendarRecord>>{};
    for (final record in records) {
      groups.putIfAbsent(_bandFor(record), () => []).add(record);
    }
    final tokens = context.themeV2;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 2, color: tokens.accent),
          const SizedBox(width: ThemeV2Spacing.lg),
          Expanded(
            child: Column(
              children: [
                for (final band in _DayBand.values)
                  if (groups[band]?.isNotEmpty ?? false)
                    _DayBandSection(
                      band: band,
                      records: groups[band]!,
                      skills: skills,
                      onOpenRecord: onOpenRecord,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static _DayBand _bandFor(CalendarRecord record) {
    switch (record.period) {
      case '上午':
      case '凌晨':
      case '中午':
        return _DayBand.morning;
      case '下午':
        return _DayBand.afternoon;
      case '晚上':
        return _DayBand.evening;
    }
    if (!record.isTimed) return _DayBand.untimed;
    if (record.effectiveAt.hour < 12) return _DayBand.morning;
    if (record.effectiveAt.hour < 18) return _DayBand.afternoon;
    return _DayBand.evening;
  }
}

class _DayBandSection extends StatelessWidget {
  const _DayBandSection({
    required this.band,
    required this.records,
    required this.skills,
    required this.onOpenRecord,
  });

  final _DayBand band;
  final List<CalendarRecord> records;
  final Map<String, SkillMeta> skills;
  final ValueChanged<CalendarRecord> onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final label = switch (band) {
      _DayBand.morning => '上午',
      _DayBand.afternoon => '下午',
      _DayBand.evening => '晚上',
      _DayBand.untimed => '没说时间',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · ${records.length}',
            style: ThemeV2Typography.mono(
              fontSize: 10,
              color: tokens.accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          for (final record in records)
            _DayRecordRow(
              record: record,
              skills: skills,
              onTap: () => onOpenRecord(record),
            ),
        ],
      ),
    );
  }
}

class _DayRecordRow extends StatelessWidget {
  const _DayRecordRow({
    required this.record,
    required this.skills,
    required this.onTap,
  });

  final CalendarRecord record;
  final Map<String, SkillMeta> skills;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final item = record.item;
    final meta = resolveMeta(item.skillName ?? item.kind, skills);
    final icon = switch (item.kind) {
      'event' => '📅',
      'contact' => '👤',
      _ => meta.icon,
    };
    return Semantics(
      label:
          '${record.isTimed ? calendarTimeLabel(record.effectiveAt) : '没说时间'}，${item.title}',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: InkWell(
            key: ValueKey('calendar-day-record-${record.id}'),
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
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
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(icon, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: ThemeV2Spacing.sm),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: tokens.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isEmpty ? '记录' : item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: tokens.foreground,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                        ),
                        if (item.subtitle.isNotEmpty)
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: tokens.muted),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
