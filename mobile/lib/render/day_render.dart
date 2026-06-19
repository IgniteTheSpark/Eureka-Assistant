import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/domains.dart';
import '../timeline/timeline.dart';

/// §4.5.0a 一天渲染 (DayRender) — the calendar-redesign wireframe's「非日程」段视图
/// (Direction B「时段水洗带」). One day's [TimelineItem]s render as up to 5
/// color-temperature bands (凌晨 / 上午 / 中午 / 下午 / 晚上); empty bands are omitted.
/// Each band = a soft 段头 + rows of [time column + 3-line card DNA]. All-day events
/// pin to a top「全天」strip; items with no clock time fall to a bottom「没说时间」group.
///
/// Reused by TodayPage, the 流 stream tile ([compact] = true), and DayDetail「非日程」.
///
/// Placement is by [TimelineItem.effectiveAt] (server = occurred_at ?? event
/// start_at ?? created_at). "No clock time" is approximated for v1 by a midnight
/// effectiveAt on a non-event; once the backend adds `period`/`occurred_at`
/// (eng-card slice 4) the predicate tightens — the band + soft-group structure
/// here already supports it. Flash (input_turn) captures are excluded — they live
/// in the ⚡N pill / DayFlashView (slice 3), not the bands.
class DayRender extends StatelessWidget {
  const DayRender({
    super.key,
    required this.items,
    required this.skills,
    this.compact = false,
    this.highlightNow = false,
    this.onTapItem,
  });

  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;

  /// 流 tile passes true → tighter paddings + smaller type so many days stack.
  final bool compact;

  /// Today only → mark the band containing the current hour as「现在」.
  final bool highlightNow;

  final void Function(TimelineItem item)? onTapItem;

  static _Band _periodOf(int hour) {
    if (hour <= 5) return _Band.dawn;
    if (hour <= 11) return _Band.morning;
    if (hour == 12) return _Band.noon;
    if (hour <= 17) return _Band.afternoon;
    return _Band.evening;
  }

  static _Band? _bandFromName(String period) {
    switch (period) {
      case '凌晨':
        return _Band.dawn;
      case '上午':
        return _Band.morning;
      case '中午':
        return _Band.noon;
      case '下午':
        return _Band.afternoon;
      case '晚上':
        return _Band.evening;
    }
    return null;
  }

  // A timed row shows a clock time: events (start_at), assets whose user stated a
  // 钟点 (hasClockTime), and the capture-time fallback all count. period-only
  // assets are NOT timed — they land in their 段's soft「没具体时间」group with no
  // time; a genuinely time-less asset (midnight, no period) drops to the bottom.
  static bool _isTimed(TimelineItem it) {
    if (it.allDay) return false;
    if (it.kind == 'event') return true;
    if (it.hasClockTime) return true;
    if (it.period.isNotEmpty) return false;
    return !(it.effectiveAt.hour == 0 && it.effectiveAt.minute == 0);
  }

  @override
  Widget build(BuildContext context) {
    // Flash captures are surfaced via the ⚡ pill, never as band cards.
    final visible = items.where((i) => i.kind != 'input_turn').toList();

    final allDay = <TimelineItem>[];
    final bandTimed = <_Band, List<TimelineItem>>{};
    final bandSoft = <_Band, List<TimelineItem>>{}; // period-only, no clock time
    final bottomNoTime = <TimelineItem>[];

    for (final it in visible) {
      if (it.allDay) {
        allDay.add(it);
      } else if (_isTimed(it)) {
        bandTimed.putIfAbsent(_periodOf(it.effectiveAt.hour), () => []).add(it);
      } else {
        final b = _bandFromName(it.period);
        (b != null ? bandSoft.putIfAbsent(b, () => []) : bottomNoTime).add(it);
      }
    }
    for (final l in bandTimed.values) {
      l.sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
    }

    if (allDay.isEmpty && bottomNoTime.isEmpty && bandTimed.isEmpty && bandSoft.isEmpty) {
      return const SizedBox.shrink();
    }

    final nowBand = highlightNow ? _periodOf(TimeOfDay.now().hour) : null;
    final children = <Widget>[];

    if (allDay.isNotEmpty) {
      children.add(_AllDayStrip(items: allDay, skills: skills, onTap: onTapItem));
      children.add(SizedBox(height: compact ? 8 : 9));
    }

    for (final def in _kBands) {
      final timed = bandTimed[def.band] ?? const <TimelineItem>[];
      final soft = bandSoft[def.band] ?? const <TimelineItem>[];
      if (timed.isEmpty && soft.isEmpty) continue;
      children.add(_BandSection(
        def: def,
        items: timed,
        soft: soft,
        skills: skills,
        compact: compact,
        isNow: def.band == nowBand,
        onTap: onTapItem,
      ));
      children.add(SizedBox(height: compact ? 8 : 9));
    }

    if (bottomNoTime.isNotEmpty) {
      children.add(_NoTimeGroup(items: bottomNoTime, skills: skills, compact: compact, onTap: onTapItem));
    } else if (children.isNotEmpty) {
      children.removeLast(); // drop the trailing gap after the last band
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/* ── bands ─────────────────────────────────────────────────────────────────── */

enum _Band { dawn, morning, noon, afternoon, evening }

class _BandDef {
  const _BandDef(this.band, this.label, this.emoji, this.tint);
  final _Band band;
  final String label;
  final String emoji;
  final Color tint; // subtle color-temperature wash over the dark surface
}

// Cool → warm → cool across the day, mapped to the dark theme as low-alpha washes.
const _kBands = <_BandDef>[
  _BandDef(_Band.dawn, '凌晨', '🌙', Color(0xFF6F9EFF)),
  _BandDef(_Band.morning, '上午', '🌅', Color(0xFFF5C977)),
  _BandDef(_Band.noon, '中午', '☀️', Color(0xFFFFD98A)),
  _BandDef(_Band.afternoon, '下午', '🌆', Color(0xFFE9A977)),
  _BandDef(_Band.evening, '晚上', '🌃', Color(0xFF8B9DFF)),
];

class _BandSection extends StatelessWidget {
  const _BandSection({
    required this.def,
    required this.items,
    required this.soft,
    required this.skills,
    required this.compact,
    required this.isNow,
    this.onTap,
  });

  final _BandDef def;
  final List<TimelineItem> items; // timed rows (clock time / capture fallback)
  final List<TimelineItem> soft; // period-only rows (no clock time)
  final Map<String, SkillMeta> skills;
  final bool compact;
  final bool isNow;
  final void Function(TimelineItem)? onTap;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final pad = compact ? 9.0 : 12.0;
    // Wash band: a faint vertical gradient of the band tint over the raised
    // surface — enough to feel the time-of-day "temperature", never loud.
    final top = Color.alphaBlend(def.tint.withValues(alpha: 0.10), eu.surfaceRaised);
    final bottom = Color.alphaBlend(def.tint.withValues(alpha: 0.04), eu.surfaceRaised);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: isNow ? Border.all(color: eu.brand.withValues(alpha: 0.55), width: 1.5) : null,
      ),
      padding: EdgeInsets.fromLTRB(pad, pad - 1, pad, pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(def.emoji, style: TextStyle(fontSize: compact ? 11 : 13)),
              const SizedBox(width: 6),
              Text(def.label,
                  style: TextStyle(
                      color: eu.textMid, fontSize: compact ? 11.5 : 13, letterSpacing: 0.4)),
              const Spacer(),
              if (isNow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(color: eu.brand, borderRadius: BorderRadius.circular(999)),
                  child: Text('现在',
                      style: euMono(fontSize: 9.5, color: Colors.white)),
                ),
            ],
          ),
          SizedBox(height: compact ? 7 : 9),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(height: compact ? 6 : 7),
            _ItemRow(item: items[i], skills: skills, compact: compact, onTap: onTap),
          ],
          // period-only rows fall into this 段's soft「没具体时间」tail (brief §2.1):
          // a very faint divider + dimmed cards, no time column.
          if (soft.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                  compact ? 34 : 40, items.isEmpty ? 0 : (compact ? 9 : 11), 0, compact ? 5 : 6),
              child: Row(
                children: [
                  Text('没具体时间',
                      style: TextStyle(color: eu.textLo, fontSize: 9, letterSpacing: 0.3)),
                  const SizedBox(width: 7),
                  Expanded(child: Container(height: 1, color: eu.rule)),
                ],
              ),
            ),
            for (var i = 0; i < soft.length; i++) ...[
              if (i > 0) SizedBox(height: compact ? 6 : 7),
              _ItemRow(
                  item: soft[i],
                  skills: skills,
                  compact: compact,
                  showTime: false,
                  muted: true,
                  onTap: onTap),
            ],
          ],
        ],
      ),
    );
  }
}

/* ── one timed row: time column + 3-line card ────────────────────────────────── */

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.skills,
    required this.compact,
    this.showTime = true,
    this.muted = false,
    this.onTap,
  });

  final TimelineItem item;
  final Map<String, SkillMeta> skills;
  final bool compact;
  final bool showTime;
  final bool muted; // soft「没说时间」cards render dimmer + dashed
  final void Function(TimelineItem)? onTap;

  String get _time =>
      '${item.effectiveAt.hour.toString().padLeft(2, '0')}:${item.effectiveAt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: compact ? 34 : 40,
          child: showTime
              ? Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(_time,
                      textAlign: TextAlign.right,
                      style: euMono(fontSize: compact ? 9.5 : 10.5, color: eu.textLo)),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(child: _DayCard(item: item, skills: skills, compact: compact, muted: muted, onTap: onTap)),
      ],
    );
  }
}

/// 3-line card DNA (spec §4.7.3 / brief): IconTile + (title + 领域 chip) + subtitle
/// + ≤2 meta. Fixed structure; long fields ellipsize and never wrap.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.item,
    required this.skills,
    required this.compact,
    this.muted = false,
    this.onTap,
  });

  final TimelineItem item;
  final Map<String, SkillMeta> skills;
  final bool compact;
  final bool muted;
  final void Function(TimelineItem)? onTap;

  String get _icon {
    switch (item.kind) {
      case 'event':
        return '📅';
      case 'contact':
        return '👤';
      default:
        return resolveMeta(item.skillName ?? 'misc', skills).icon;
    }
  }

  String? get _domain {
    final d = item.payload['domain'];
    return d is String && d.isNotEmpty ? d : null;
  }

  // ≤2 meta. Events show their time range + location; others reuse the item's
  // location if present. (Skill-specific meta arrives with render-spec wiring.)
  List<String> get _meta {
    final out = <String>[];
    if (item.kind == 'event') {
      final s = item.effectiveAt;
      final e = item.endAt;
      String hm(DateTime t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      out.add(e != null ? '${hm(s)}–${hm(e)}' : hm(s));
    }
    final loc = item.location;
    if (loc != null && loc.isNotEmpty) out.add('📍 $loc');
    return out.take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final dom = _domain;
    final accent = dom != null ? domainColor(eu, dom) : eu.textLo;
    final meta = _meta;
    final tileSize = compact ? 28.0 : 30.0;

    final card = Container(
      decoration: BoxDecoration(
        color: muted ? eu.surface.withValues(alpha: 0.55) : eu.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: muted ? eu.border.withValues(alpha: 0.7) : eu.border,
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 10, vertical: compact ? 7 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: tileSize,
            height: tileSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
            ),
            child: Text(_icon, style: TextStyle(fontSize: compact ? 13 : 14)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ① title row — title (1 line, ellipsis) + 领域 tag pinned right
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title.isEmpty ? '记录' : item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: eu.textHi, fontSize: compact ? 12.5 : 13),
                      ),
                    ),
                    if (dom != null) ...[const SizedBox(width: 7), DomainChip(dom)],
                  ],
                ),
                // ② subtitle — single line
                if (item.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: eu.textMid, fontSize: compact ? 10 : 10.5)),
                ],
                // ③ info row — ≤2 meta, equal-width, never wrap
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      for (var i = 0; i < meta.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: Text(meta[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: euMono(fontSize: 9, color: eu.textLo)),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap!(item),
      child: card,
    );
  }
}

/* ── top「全天」strip ─────────────────────────────────────────────────────────── */

class _AllDayStrip extends StatelessWidget {
  const _AllDayStrip({required this.items, required this.skills, this.onTap});
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final void Function(TimelineItem)? onTap;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final amber = domainColor(eu, '生活');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap == null ? null : () => onTap!(it),
              child: Container(
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: amber.withValues(alpha: 0.3), width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Text('全天', style: euMono(fontSize: 9.5, color: amber, letterSpacing: 0.5)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(it.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: eu.textHi, fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ── bottom「没说时间」soft group ─────────────────────────────────────────────── */

class _NoTimeGroup extends StatelessWidget {
  const _NoTimeGroup({required this.items, required this.skills, required this.compact, this.onTap});
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final bool compact;
  final void Function(TimelineItem)? onTap;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // very quiet divider — softer than a section header (brief §4.2)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Row(
            children: [
              Text('没说时间',
                  style: TextStyle(color: eu.textLo, fontSize: 9.5, letterSpacing: 0.4)),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: eu.rule)),
            ],
          ),
        ),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 6 : 7),
          _ItemRow(item: items[i], skills: skills, compact: compact, showTime: false, muted: true, onTap: onTap),
        ],
      ],
    );
  }
}
