import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import 'notifications_page.dart';

/// Calendar surface with a 流 / 月 / 年 segmented control over GET /api/timeline.
/// 流 = schedule list (flash captures render as ⚡ + derived breakdown);
/// 月 = dot grid + selected-day list; 年 = 12-month grid.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalData {
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final Map<DateTime, List<TimelineItem>> byDay;
  _CalData(this.items, this.skills) : byDay = _bucket(items);

  static Map<DateTime, List<TimelineItem>> _bucket(List<TimelineItem> items) {
    final m = <DateTime, List<TimelineItem>>{};
    for (final it in items) {
      final d = DateTime(it.effectiveAt.year, it.effectiveAt.month, it.effectiveAt.day);
      m.putIfAbsent(d, () => []).add(it);
    }
    for (final v in m.values) {
      v.sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
    }
    return m;
  }
}

class _CalendarPageState extends State<CalendarPage> {
  final _api = ApiClient();
  late Future<_CalData> _future = _load();

  String _mode = 'timeline'; // timeline | month | year
  late DateTime _focusMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  Future<_CalData> _load() async {
    final r = await Future.wait([fetchTimeline(_api), fetchSkills(_api)]);
    return _CalData(r[0] as List<TimelineItem>, r[1] as Map<String, SkillMeta>);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  _Segmented(
                    value: _mode,
                    onChanged: (v) => setState(() => _mode = v),
                  ),
                  const Spacer(),
                  IconButton(
                      onPressed: _refresh,
                      tooltip: '刷新',
                      icon: Icon(Icons.refresh, color: eu.textMid)),
                  const NotificationsBell(),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_CalData>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('加载失败：${snap.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: eu.accentRed)),
                      ),
                    );
                  }
                  final data = snap.data!;
                  switch (_mode) {
                    case 'month':
                      return _MonthView(
                        month: _focusMonth,
                        byDay: data.byDay,
                        skills: data.skills,
                        selected: _selectedDay,
                        onSelect: (d) => setState(() => _selectedDay = d),
                        onPrevNext: (delta) => setState(() {
                          _focusMonth = DateTime(_focusMonth.year, _focusMonth.month + delta);
                          _selectedDay = null;
                        }),
                      );
                    case 'year':
                      return _YearView(
                        year: _focusMonth.year,
                        byDay: data.byDay,
                        onPickMonth: (m) => setState(() {
                          _focusMonth = m;
                          _mode = 'month';
                          _selectedDay = null;
                        }),
                      );
                    default:
                      return _TimelineView(data: data);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ── 流 / 月 / 年 segmented control ──────────────────────────────────────── */

class _Segmented extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _Segmented({required this.value, required this.onChanged});

  static const _opts = [('timeline', '流'), ('month', '月'), ('year', '年')];

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _opts)
            GestureDetector(
              onTap: () => onChanged(o.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: value == o.$1 ? eu.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(o.$2,
                    style: TextStyle(
                        color: value == o.$1 ? Colors.white : eu.textMid,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

/* ── 流 timeline ────────────────────────────────────────────────────────── */

class _TimelineView extends StatelessWidget {
  final _CalData data;
  const _TimelineView({required this.data});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    if (data.items.isEmpty) {
      return Center(child: Text('还没有内容', style: TextStyle(color: eu.textMid)));
    }
    final days = groupByDay(data.items);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 80),
      itemCount: days.length,
      itemBuilder: (_, i) =>
          _DayRow(day: days[i].key, items: days[i].value, skills: data.skills),
    );
  }
}

/* ── 月 month grid + selected-day list ──────────────────────────────────── */

class _MonthView extends StatelessWidget {
  final DateTime month; // first of month
  final Map<DateTime, List<TimelineItem>> byDay;
  final Map<String, SkillMeta> skills;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onPrevNext;
  const _MonthView({
    required this.month,
    required this.byDay,
    required this.skills,
    required this.selected,
    required this.onSelect,
    required this.onPrevNext,
  });

  static const _wd = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final first = DateTime(month.year, month.month, 1);
    final daysIn = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday-first
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= daysIn; d++) DateTime(month.year, month.month, d),
    ];
    final selDay = selected;
    final selItems = selDay == null ? const <TimelineItem>[] : (byDay[selDay] ?? const []);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        Row(
          children: [
            IconButton(
                onPressed: () => onPrevNext(-1),
                icon: Icon(Icons.chevron_left, color: eu.textMid)),
            Expanded(
              child: Center(
                child: Text('${month.year} 年 ${month.month} 月',
                    style: TextStyle(
                        color: eu.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            IconButton(
                onPressed: () => onPrevNext(1),
                icon: Icon(Icons.chevron_right, color: eu.textMid)),
          ],
        ),
        Row(
          children: [
            for (final w in _wd)
              Expanded(
                child: Center(
                  child: Text(w, style: TextStyle(color: eu.textLo, fontSize: 11)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final d in cells)
              if (d == null)
                const SizedBox.shrink()
              else
                _DayCell(
                  day: d,
                  dotColor: _dominantColor(byDay[d], context.eu),
                  isToday: d.year == now.year && d.month == now.month && d.day == now.day,
                  isSelected: selDay != null && d == selDay,
                  onTap: () => onSelect(d),
                ),
          ],
        ),
        const SizedBox(height: 12),
        if (selDay != null) ...[
          Text('${selDay.month}月${selDay.day}日 · ${selItems.length} 件事',
              style: TextStyle(color: eu.textMid, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (selItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('空闲', style: TextStyle(color: eu.textLo)),
            )
          else
            for (final it in selItems) _ItemRow(item: it, skills: skills),
        ] else
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('点选某天查看', style: TextStyle(color: eu.textLo, fontSize: 13)),
            ),
          ),
      ],
    );
  }
}

/// Dominant accent for a day's dot (event purple > todo blue > expense green >
/// idea amber > brand). Null when the day has no items.
Color? _dominantColor(List<TimelineItem>? items, EurekaColors eu) {
  if (items == null || items.isEmpty) return null;
  bool has(bool Function(TimelineItem) f) => items.any(f);
  if (has((it) => it.kind == 'event' || it.skillName == 'event')) return eu.accentPurple;
  if (has((it) => it.skillName == 'todo')) return eu.accentBlue;
  if (has((it) => it.skillName == 'expense')) return eu.accentGreen;
  if (has((it) => it.skillName == 'idea')) return eu.accentAmber;
  return eu.brand;
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final Color? dotColor;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.dotColor,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isToday
              ? eu.brand
              : isSelected
                  ? eu.brand.withValues(alpha: 0.16)
                  : Colors.transparent,
          shape: BoxShape.circle,
          border: isSelected && !isToday ? Border.all(color: eu.brand) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${day.day}',
                style: TextStyle(
                    color: isToday ? Colors.white : eu.textHi, fontSize: 13)),
            if (dotColor != null)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                    color: isToday ? Colors.white : dotColor, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

/* ── 年 month grid ──────────────────────────────────────────────────────── */

class _YearView extends StatelessWidget {
  final int year;
  final Map<DateTime, List<TimelineItem>> byDay;
  final ValueChanged<DateTime> onPickMonth;
  const _YearView({required this.year, required this.byDay, required this.onPickMonth});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final counts = List<int>.filled(12, 0);
    byDay.forEach((d, items) {
      if (d.year == year) counts[d.month - 1] += items.length;
    });
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      childAspectRatio: 1.2,
      children: [
        for (var m = 1; m <= 12; m++)
          GestureDetector(
            onTap: () => onPickMonth(DateTime(year, m)),
            child: Container(
              margin: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: eu.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: eu.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$m 月',
                      style: TextStyle(
                          color: eu.textHi, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(counts[m - 1] > 0 ? '${counts[m - 1]} 件' : '—',
                      style: TextStyle(
                          color: counts[m - 1] > 0 ? eu.brand : eu.textLo, fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/* ── shared day section + item row (流 + 月) ────────────────────────────── */

/// A day in the 流: a left date rail (weekday cap + big date, today brand line
/// + glow) beside a colored tile (brand-faint gradient) holding the day's rows.
/// Mirrors the web ScheduleView.
class _DayRow extends StatelessWidget {
  final DateTime day;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  const _DayRow({required this.day, required this.items, required this.skills});

  static const _wd = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 54, child: _rail(eu, isToday)),
            Expanded(child: _tile(eu)),
          ],
        ),
      ),
    );
  }

  Widget _rail(EurekaColors eu, bool isToday) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_wd[day.weekday % 7],
                  style: euMono(
                      fontSize: 9.5, letterSpacing: 1.4, color: isToday ? eu.brand : eu.textLo)),
              const SizedBox(height: 2),
              Text('${day.day}',
                  style: TextStyle(
                    fontSize: isToday ? 22 : 18,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday ? eu.brand : eu.textHi,
                    shadows: isToday
                        ? [Shadow(color: eu.brand.withValues(alpha: 0.5), blurRadius: 12)]
                        : null,
                  )),
            ],
          ),
        ),
        if (isToday)
          Positioned(
            right: 0,
            top: 8,
            bottom: 8,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: eu.brand,
                boxShadow: [BoxShadow(color: eu.brand.withValues(alpha: 0.6), blurRadius: 8)],
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(EurekaColors eu) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(eu.brand.withValues(alpha: 0.10), eu.surfaceRaised),
            eu.surfaceRaised,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: eu.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: eu.brightness == Brightness.dark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _TileItemRow(item: items[i], skills: skills),
          ],
        ],
      ),
    );
  }
}

/// A single row inside a 流 day tile (no own background).
class _TileItemRow extends StatelessWidget {
  final TimelineItem item;
  final Map<String, SkillMeta> skills;
  const _TileItemRow({required this.item, required this.skills});

  String get _time =>
      '${item.effectiveAt.hour.toString().padLeft(2, '0')}:${item.effectiveAt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final isFlash = item.kind == 'input_turn';
    final entries =
        isFlash ? item.derived.entries.where((e) => e.value > 0).toList() : const [];
    final icon = isFlash
        ? '⚡'
        : item.kind == 'event'
            ? '📅'
            : item.kind == 'contact'
                ? '👤'
                : resolveMeta(item.skillName ?? 'misc', skills).icon;
    final primary = isFlash
        ? (entries.isEmpty
            ? (item.title.isEmpty ? '闪念' : item.title)
            : entries.map((e) {
                final m = resolveMeta(e.key, skills);
                return '${m.icon} ${m.label}×${e.value}';
              }).join('  ·  '))
        : item.title;
    final secondary =
        isFlash ? (entries.isNotEmpty ? item.title : '') : item.subtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 40, child: Text(_time, style: euMono(fontSize: 10.5, color: eu.textLo))),
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(primary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: eu.textHi, fontSize: 13.5, fontWeight: FontWeight.w500)),
              if (secondary.isNotEmpty)
                Text(secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: eu.textMid, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final TimelineItem item;
  final Map<String, SkillMeta> skills;
  const _ItemRow({required this.item, required this.skills});

  String get _time =>
      '${item.effectiveAt.hour.toString().padLeft(2, '0')}:${item.effectiveAt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    if (item.kind == 'input_turn') return _flash(eu);
    final icon = item.kind == 'event'
        ? '📅'
        : item.kind == 'contact'
            ? '👤'
            : resolveMeta(item.skillName ?? 'misc', skills).icon;
    return _shell(eu, crossStart: false, child: _content(eu, icon, item.title, item.subtitle));
  }

  Widget _flash(EurekaColors eu) {
    final entries = item.derived.entries.where((e) => e.value > 0).toList();
    final breakdown = entries.map((e) {
      final m = resolveMeta(e.key, skills);
      return '${m.icon} ${m.label}×${e.value}';
    }).join('  ·  ');
    final primary = entries.isEmpty ? (item.title.isEmpty ? '闪念' : item.title) : breakdown;
    final secondary = entries.isNotEmpty ? item.title : '';
    return _shell(eu, crossStart: true, child: _content(eu, '⚡', primary, secondary));
  }

  Widget _shell(EurekaColors eu, {required bool crossStart, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        crossAxisAlignment:
            crossStart ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 42,
            child: Text(_time, style: TextStyle(color: eu.textLo, fontSize: 11)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _content(EurekaColors eu, String icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w500)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: eu.textMid, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
