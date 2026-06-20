import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../timeline/timeline.dart';
import 'session_detail_page.dart';

/// §4.5.0b 当日闪念视图 — the day's raw flash captures, pulled OUT of the timeline
/// bands (DayRender excludes `input_turn`) and gathered here behind the ⚡N pill.
/// Reverse-chronological; each row = 时刻 + transcript 摘要 + 产出卡 breakdown
/// (provenance). Tapping a capture opens its replay session.
class DayFlashView extends StatelessWidget {
  const DayFlashView({
    super.key,
    required this.day,
    required this.flashes,
    required this.skills,
  });

  final DateTime day;
  final List<TimelineItem> flashes; // kind == 'input_turn'
  final Map<String, SkillMeta> skills;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final items = [...flashes]..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
    return Scaffold(
      backgroundColor: eu.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: eu.textHi),
                    tooltip: '返回',
                  ),
                  const SizedBox(width: 2),
                  Text('⚡', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 7),
                  Text('${day.month}月${day.day}日 · ${items.length} 条闪念',
                      style: TextStyle(color: eu.textHi, fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('这天还没有闪念', style: TextStyle(color: eu.textLo, fontSize: 14)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (_, i) => _FlashRow(item: items[i], skills: skills),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlashRow extends StatelessWidget {
  const _FlashRow({required this.item, required this.skills});
  final TimelineItem item;
  final Map<String, SkillMeta> skills;

  String get _time =>
      '${item.effectiveAt.hour.toString().padLeft(2, '0')}:${item.effectiveAt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final summary = item.title.isNotEmpty
        ? item.title
        : item.subtitle.isNotEmpty
            ? item.subtitle
            : '闪念';
    final produced = item.derived.entries.where((e) => e.value > 0).toList();
    final sid = item.sessionId;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: sid == null || sid.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SessionDetailPage(
                    sessionId: sid, title: '${item.effectiveAt.month}月${item.effectiveAt.day}日 闪念'),
              )),
      child: Container(
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: eu.border),
        ),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('⚡', style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 7),
                Text(_time, style: euMono(fontSize: 11, color: eu.textMid)),
                const Spacer(),
                Icon(Icons.chevron_right, size: 16, color: eu.textLo),
              ],
            ),
            const SizedBox(height: 7),
            Text(summary,
                style: TextStyle(color: eu.textHi, fontSize: 14, height: 1.35)),
            if (produced.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in produced)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: eu.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: eu.border),
                      ),
                      child: Text('${resolveMeta(e.key, skills).icon} ${resolveMeta(e.key, skills).label}×${e.value}',
                          style: TextStyle(color: eu.textMid, fontSize: 10.5)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The ⚡N闪念 entry pill — pinned on every「日 header」(DayDetail / 流 rail /
/// today). N=0 → renders nothing. Tap → [DayFlashView] for that day.
class FlashPill extends StatelessWidget {
  const FlashPill({
    super.key,
    required this.day,
    required this.flashes,
    required this.skills,
    this.compact = false,
  });

  final DateTime day;
  final List<TimelineItem> flashes;
  final Map<String, SkillMeta> skills;
  final bool compact; // 流 rail = compact (just ⚡N), no「条闪念」label

  static List<TimelineItem> flashesIn(List<TimelineItem> items) =>
      items.where((i) => i.kind == 'input_turn').toList();

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final n = flashes.length;
    if (n == 0) return const SizedBox.shrink();
    // 闪念是主功能 → pill 做大、易点。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 5 : 7),
        constraints: BoxConstraints(minHeight: compact ? 28 : 34),
        // §design 闪念表达:白底浅蓝描边胶囊「⚡ N 闪念」(= chat 入口)。
        decoration: BoxDecoration(
          color: Color.alphaBlend(eu.brand.withValues(alpha: 0.10), eu.surfaceRaised),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: eu.brand.withValues(alpha: 0.5), width: 1.3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('⚡', style: TextStyle(fontSize: compact ? 13 : 15)),
            SizedBox(width: compact ? 3 : 4),
            Text('$n',
                style: euMono(
                    fontSize: compact ? 12.5 : 13.5,
                    fontWeight: FontWeight.w700,
                    color: eu.brand)),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    // §design 闪念 = chat 入口:直接进当天的「X月X日 闪念」session,不再过当日列表页。
    // 多条 → 进最近一条有 session 的捕捉(就是那天的 闪念 对话)。
    final sorted = [...flashes]..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
    final f = sorted.firstWhere(
        (x) => (x.sessionId?.isNotEmpty ?? false),
        orElse: () => sorted.first);
    final sid = f.sessionId;
    if (sid == null || sid.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionDetailPage(
          sessionId: sid, title: '${day.month}月${day.day}日 闪念'),
    ));
  }
}
