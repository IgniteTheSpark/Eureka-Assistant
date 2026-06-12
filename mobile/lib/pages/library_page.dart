import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import '../widgets/toast.dart';
import 'add_skill.dart';
import 'category_detail_page.dart';
import 'entity_list_page.dart';
import 'report_list_page.dart';
import 'skill_manage_page.dart';

/// Library hub — mirrors the web CategoryList: a hero header (total count) over
/// three sections: 常驻 (first-class entity tiles), 启用的技能 (skill grid), and
/// 最近 (cross-type recent cards grouped by day).
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibData {
  final List<AssetItem> assets;
  final Map<String, SkillMeta> skills;
  // Full records (not just counts) so 最近 can merge events/contacts with
  // assets — first-class entities live in their own tables, never in /api/assets.
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> contacts;
  final List<Map<String, dynamic>> reports;
  // True per-skill **total** asset counts (all-time, from /api/assets/counts) —
  // container tiles show totals, not「最近 50 条里碰巧有几条」(`assets` is capped).
  final Map<String, int> assetCounts;
  _LibData(this.assets, this.skills, this.events, this.contacts, this.reports,
      this.assetCounts);

  int get eventCount => events.length;
  int get contactCount => contacts.length;
  int get assetTotal => assetCounts.values.fold(0, (a, b) => a + b);
  int get total => assetTotal + eventCount + contactCount;
}

/// One row in the cross-type 最近 list. `card` is the SkillCard payload (assets
/// carry user_skill_name; events/contacts/files carry a `card_type`).
class _RecentEntry {
  final DateTime createdAt;
  final Map<String, dynamic> card;
  _RecentEntry(this.createdAt, this.card);
}

DateTime _parseTs(Map m) =>
    DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now();

// Skills never shown in the SKILLS grid (system / first-class).
const _hiddenSkills = {'external_ref', 'qa', 'contact'};

// Built-in systemic skills surfaced in the 常驻 row (not the custom-skill grid):
// the always-present capture skills. They still count toward the active cap.
const _systemicSkills = {'todo', 'notes'};

// Active-set cap — keep in sync with backend `ACTIVE_SKILL_CAP` (api/skills.py).
// The grid shows only active skills; the 新技能 tile shows 活跃数/上限.
const _activeCap = 9;

class _LibraryPageState extends State<LibraryPage> {
  final _api = ApiClient();
  // Revision-keyed fetch: build() re-subscribes to `dataRevision` every frame
  // via ValueListenableBuilder, so a data change always re-fetches — and unlike
  // an initState-registered listener, this survives hot-reload (build re-runs).
  int _loadedRev = -1;
  Future<_LibData>? _future;

  Future<_LibData> _futureFor(int rev) {
    if (rev != _loadedRev || _future == null) {
      _loadedRev = rev;
      _future = _load();
    }
    return _future!;
  }

  Future<_LibData> _load() async {
    final r = await Future.wait([
      fetchAssets(_api),
      fetchSkills(_api),
      _fetchList('/api/events', 'events'),
      _fetchList('/api/contacts', 'contacts'),
      _fetchList('/api/reports', 'reports'),
      _fetchCounts(),
    ]);
    return _LibData(
      r[0] as List<AssetItem>,
      r[1] as Map<String, SkillMeta>,
      r[2] as List<Map<String, dynamic>>,
      r[3] as List<Map<String, dynamic>>,
      r[4] as List<Map<String, dynamic>>,
      r[5] as Map<String, int>,
    );
  }

  /// True per-skill total asset counts (all-time) for the container tiles.
  Future<Map<String, int>> _fetchCounts() async {
    try {
      final res = await _api.getJson('/api/assets/counts');
      final m = (res is Map ? res['counts'] : null) as Map? ?? const {};
      return m.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> _fetchList(String path, String key) async {
    try {
      final res = await _api.getJson(path);
      final list = (res is Map ? res[key] : null) as List? ?? const [];
      return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  void _refresh() => bumpData(); // global bump → revision changes → re-fetch

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
        child: ValueListenableBuilder<int>(
          valueListenable: dataRevision,
          builder: (context, rev, _) => FutureBuilder<_LibData>(
            future: _futureFor(rev),
            builder: (ctx, snap) {
              final data = snap.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(eu, data?.total),
                  Expanded(
                    child: snap.connectionState != ConnectionState.done
                        ? const Center(child: CircularProgressIndicator())
                        : snap.hasError
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text('加载失败：${snap.error}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: eu.accentRed)),
                                ),
                              )
                            : _body(eu, data!),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(EurekaColors eu, int? total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('资产库',
                    style: TextStyle(
                        color: eu.textHi,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('${total ?? '·'} ITEMS · 总计',
                    style: euMono(fontSize: 10.5, letterSpacing: 1.6, color: eu.textLo)),
              ],
            ),
          ),
          IconButton(
              onPressed: _exporting ? null : _exportMenu,
              tooltip: '导出',
              icon: _exporting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: eu.textMid))
                  : Icon(Icons.ios_share, color: eu.textMid)),
          IconButton(
              onPressed: _refresh,
              tooltip: '刷新',
              icon: Icon(Icons.refresh, color: eu.textMid)),
        ],
      ),
    );
  }

  // 导出 — pick which types to include + the format, then hand the file to the
  // native share sheet. NOT a default full dump.
  bool _exporting = false;

  Future<void> _exportMenu() async {
    final data = await (_future ?? _load());
    if (!mounted) return;
    // Available types = asset skills that actually have records + 事件 / 名片.
    final counts = data.assetCounts;
    final types = <ExportType>[];
    counts.forEach((k, n) {
      final m = resolveMeta(k, data.skills);
      types.add(ExportType(k, m.label, m.icon, n));
    });
    if (data.events.isNotEmpty) types.add(ExportType('event', '事件', '📅', data.events.length));
    if (data.contacts.isNotEmpty) types.add(ExportType('contact', '名片', '👤', data.contacts.length));
    if (types.isEmpty) {
      showToast(context, '还没有可导出的内容');
      return;
    }
    final eu = context.eu;
    final result = await showModalBottomSheet<({String format, Set<String> types})>(
      context: context,
      backgroundColor: eu.surfaceRaised,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ExportSheet(types: types),
    );
    if (result != null && result.types.isNotEmpty) await _export(result.format, result.types);
  }

  Future<void> _export(String format, Set<String> types) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final text = await _api.getText('/api/export',
          query: {'format': format, 'types': types.join(',')});
      final ext = format == 'csv' ? 'csv' : 'md';
      final mime = format == 'csv' ? 'text/csv' : 'text/markdown';
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}';
      final name = 'eureka_export_$stamp.$ext';
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsString(text);
      await Share.shareXFiles([XFile(file.path, mimeType: mime, name: name)],
          subject: 'UReka 导出');
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _body(EurekaColors eu, _LibData data) {
    // True totals (all-time) for every container tile — not the capped list.
    final bySkill = data.assetCounts;
    // All active (enabled, non-system) skills — drives the active-cap display.
    final gridSkills = data.skills.entries
        .where((e) => !_hiddenSkills.contains(e.key) && e.value.enabled)
        .toList();
    // Cap-eligible skills = optional ones (记账 + custom). The 常驻 built-ins
    // (待办/随记) live in 常驻 and don't count toward the 9-cap.
    final customGrid =
        gridSkills.where((e) => !_systemicSkills.contains(e.key)).toList();

    final todoMeta = data.skills['todo'] ?? const SkillMeta('✅', '待办', 'blue');
    final suijiMeta = data.skills['notes'] ?? const SkillMeta('✍️', '随记', 'amber');

    final recent = _buildRecent(data)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentTop = recent.take(12).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        const _SectionLabel('常驻 · PERMANENT'),
        const SizedBox(height: 8),
        // The always-present systemic skills + first-class entities.
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            _skillTile(eu, todoMeta, bySkill['todo'] ?? 0,
                () => _openSkill(data, 'todo', todoMeta)),
            _skillTile(eu, suijiMeta, bySkill['notes'] ?? 0,
                () => _openSkill(data, 'notes', suijiMeta)),
            _skillTile(eu, const SkillMeta('📅', '事件', 'purple'), data.eventCount,
                () => _openEntity('事件', '/api/events', 'events', 'event')),
            _skillTile(eu, const SkillMeta('👤', '名片', 'neutral'), data.contactCount,
                () => _openEntity('名片', '/api/contacts', 'contacts', 'contact')),
            _skillTile(eu, const SkillMeta('🔗', '外部', 'blue'),
                bySkill['external_ref'] ?? 0,
                () => _openSkill(data, 'external_ref', const SkillMeta('🔗', '外部', 'blue'))),
            _skillTile(eu, const SkillMeta('📊', '报告', 'purple'), data.reports.length,
                () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ReportListPage()))),
          ],
        ),
        const SizedBox(height: 18),
        _SectionLabel('活跃技能 · SKILLS',
            trailing: GestureDetector(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SkillManagePage())),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 13, color: eu.textMid),
                  const SizedBox(width: 4),
                  Text('全部技能',
                      style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textMid)),
                ],
              ),
            )),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            _addTile(eu, customGrid.length),
            for (final e in customGrid)
              _skillTile(eu, e.value, bySkill[e.key] ?? 0,
                  () => _openSkill(data, e.key, e.value)),
          ],
        ),
        const SizedBox(height: 18),
        const _SectionLabel('最近 · RECENT'),
        const SizedBox(height: 6),
        if (recentTop.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('还没有资产 — 用底部 + 或 ⚡ 创建',
                style: euMono(fontSize: 11, color: eu.textLo)),
          )
        else
          ..._recentByDay(recentTop),
      ],
    );
  }

  /// Merge every freshly-created thing (assets + events + contacts) into one
  /// cross-type list keyed by created_at. First-class entities (events/contacts)
  /// never reach /api/assets, which is why they were previously absent from 最近.
  List<_RecentEntry> _buildRecent(_LibData d) {
    final out = <_RecentEntry>[
      for (final a in d.assets)
        _RecentEntry(a.createdAt, {
          'user_skill_name': a.skillName,
          'payload': a.payload,
          'asset_id': a.id,
          'session_id': a.sessionId,
          'domain': a.domain,
        }),
      for (final e in d.events) _RecentEntry(_parseTs(e), {'card_type': 'event', ...e}),
      for (final c in d.contacts) _RecentEntry(_parseTs(c), {'card_type': 'contact', ...c}),
    ];
    return out;
  }

  List<Widget> _recentByDay(List<_RecentEntry> items) {
    final out = <Widget>[];
    final now = DateTime.now();
    String? lastKey;
    for (final it in items) {
      final d = DateTime(it.createdAt.year, it.createdAt.month, it.createdAt.day);
      final key = d.toIso8601String();
      if (key != lastKey) {
        lastKey = key;
        final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
        final y = now.subtract(const Duration(days: 1));
        final isYesterday = d.year == y.year && d.month == y.month && d.day == y.day;
        final label = isToday ? '今天' : isYesterday ? '昨天' : '${d.month}月${d.day}日';
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(label, style: euMono(fontSize: 10, letterSpacing: 1.2, color: context.eu.textLo)),
        ));
      }
      out.add(SkillCard(it.card, layoutOverride: 'horizontal'));
    }
    return out;
  }

  void _openEntity(String title, String endpoint, String listKey, String cardType) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EntityListPage(
        title: title,
        endpoint: endpoint,
        listKey: listKey,
        toCard: (e) => {'card_type': cardType, ...e},
      ),
    ));
  }

  void _openSkill(_LibData data, String key, SkillMeta meta) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CategoryDetailPage(
        meta: meta,
        skillName: key,
        assets: data.assets.where((a) => a.skillName == key).toList(),
      ),
    ));
  }

  Widget _skillTile(EurekaColors eu, SkillMeta meta, int count, VoidCallback onTap) {
    final accent = _accent(eu, meta.accentColor);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.07), eu.surfaceRaised],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: 0.20), accent.withValues(alpha: 0.06)],
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: accent.withValues(alpha: 0.32)),
              ),
              child: Text(meta.icon, style: const TextStyle(fontSize: 19)),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(meta.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text('$count', style: euMono(fontSize: 13, color: accent)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _addTile(EurekaColors eu, int count) {
    final full = count >= _activeCap;
    return GestureDetector(
      onTap: () => showAddSkill(context),
      // Dashed brand border = a clear「添加新的」affordance (foregroundPainter
      // so it draws over the tinted fill).
      child: CustomPaint(
        foregroundPainter: _DashedBorder(
          color: eu.brand.withValues(alpha: full ? 0.30 : 0.55),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [eu.brand.withValues(alpha: 0.06), eu.accentPurple.withValues(alpha: 0.02)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [eu.brand.withValues(alpha: 0.18), eu.accentPurple.withValues(alpha: 0.06)],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: eu.brand.withValues(alpha: 0.30)),
                ),
                child: const Text('✨', style: TextStyle(fontSize: 18)),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text('新技能',
                        style: TextStyle(
                            color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  // 当前数量 / 上限 —— 满了用红色提示。
                  Text('$count/$_activeCap',
                      style: euMono(
                          fontSize: 12,
                          color: full ? eu.accentRed : eu.brand)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accent(EurekaColors eu, String name) => switch (name) {
        'blue' => eu.accentBlue,
        'amber' => eu.accentAmber,
        'green' => eu.accentGreen,
        'red' => eu.accentRed,
        'purple' => eu.accentPurple,
        _ => eu.textMid,
      };
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Row(
      children: [
        Text(text, style: euMono(fontSize: 10.5, letterSpacing: 2.2, color: eu.textMid)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: eu.rule)),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

/// Dashed rounded-rect border for the「新技能」tile — signals「添加」without a
/// heavy solid frame.
class _DashedBorder extends CustomPainter {
  final Color color;
  _DashedBorder({required this.color});

  static const _radius = 16.0;
  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final src = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(_radius)));
    final dest = Path();
    for (final metric in src.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final len = math.min(_dash, metric.length - d);
        dest.addPath(metric.extractPath(d, d + len), Offset.zero);
        d += _dash + _gap;
      }
    }
    canvas.drawPath(dest, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}

/// One selectable type in the 导出 sheet (asset skill or 事件/名片).
class ExportType {
  final String key;
  final String label;
  final String icon;
  final int count;
  const ExportType(this.key, this.label, this.icon, this.count);
}

/// 导出 sheet: pick which types to include + the format. Returns
/// `(format, types)` on confirm (null if dismissed). Default = all types checked.
class _ExportSheet extends StatefulWidget {
  final List<ExportType> types;
  const _ExportSheet({required this.types});
  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late final Set<String> _sel = {...widget.types.map((t) => t.key)};
  String _format = 'md';

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final allOn = _sel.length == widget.types.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('导出',
                    style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    if (allOn) {
                      _sel.clear();
                    } else {
                      _sel
                        ..clear()
                        ..addAll(widget.types.map((t) => t.key));
                    }
                  }),
                  child: Text(allOn ? '全不选' : '全选',
                      style: TextStyle(color: eu.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('选择类型', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [for (final t in widget.types) _typeRow(eu, t)]),
              ),
            ),
            const SizedBox(height: 14),
            Text('格式', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 6),
            Row(
              children: [
                _fmtChip(eu, 'md', 'Markdown', '按类型分组,易读'),
                const SizedBox(width: 8),
                _fmtChip(eu, 'csv', 'CSV', '扁平表,易分析'),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _sel.isEmpty
                  ? null
                  : () => Navigator.of(context).pop((format: _format, types: _sel)),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _sel.isEmpty ? eu.surface : eu.brand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_sel.isEmpty ? '选一个类型' : '导出 ${_sel.length} 类',
                    style: TextStyle(
                        color: _sel.isEmpty ? eu.textLo : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeRow(EurekaColors eu, ExportType t) {
    final on = _sel.contains(t.key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => on ? _sel.remove(t.key) : _sel.add(t.key)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(on ? Icons.check_box : Icons.check_box_outline_blank,
                size: 22, color: on ? eu.brand : eu.textLo),
            const SizedBox(width: 10),
            Text(t.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(t.label, style: TextStyle(color: eu.textHi, fontSize: 15))),
            Text('${t.count}', style: euMono(fontSize: 11, color: eu.textLo)),
          ],
        ),
      ),
    );
  }

  Widget _fmtChip(EurekaColors eu, String key, String label, String sub) {
    final sel = _format == key;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _format = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: sel ? eu.brand.withValues(alpha: 0.14) : eu.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: sel ? eu.brand.withValues(alpha: 0.6) : eu.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: sel ? eu.brand : eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: eu.textLo, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
