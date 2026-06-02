import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import 'notifications_page.dart';

/// Calendar surface — the 流 (schedule) view over GET /api/timeline. Flash
/// captures render as ⚡ + a derived breakdown (待办×2 · 联系人×1) resolved via
/// the skill registry. Month / year + day-color tiles are later polish.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalData {
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  _CalData(this.items, this.skills);
}

class _CalendarPageState extends State<CalendarPage> {
  final _api = ApiClient();
  late Future<_CalData> _future = _load();

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
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Text('日历',
                      style: TextStyle(
                          color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w700)),
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
                  if (data.items.isEmpty) {
                    return Center(
                        child: Text('还没有内容', style: TextStyle(color: eu.textMid)));
                  }
                  final days = groupByDay(data.items);
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: days.length,
                    itemBuilder: (_, i) => _DaySection(
                        day: days[i].key, items: days[i].value, skills: data.skills),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final DateTime day;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  const _DaySection({required this.day, required this.items, required this.skills});

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    final label = '${day.month}月${day.day}日 · ${_weekdays[day.weekday - 1]}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(
            children: [
              Text(label,
                  style: TextStyle(
                      color: isToday ? eu.brand : eu.textMid,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: eu.brand.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('今天',
                      style: TextStyle(
                          color: eu.brand, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
        for (final it in items) _ItemRow(item: it, skills: skills),
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
    return _shell(
      eu,
      crossStart: false,
      child: _content(eu, icon, item.title, item.subtitle),
    );
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
