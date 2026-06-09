import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import '../widgets/toast.dart';
import 'connected_apps_page.dart';
import 'skill_config_page.dart';

/// Assets of one skill category. Self-fetches by [skillName] and refreshes on
/// [dataRevision] (so newly created/edited/deleted records show without leaving
/// the page). Seeds from the snapshot passed at navigation for an instant first
/// paint. Tap a card → its detail sheet (handled by [SkillCard]). For
/// registered, non-protected user skills the app bar shows a 🗑 delete control.
class CategoryDetailPage extends StatefulWidget {
  final SkillMeta meta;

  /// Initial assets (snapshot from the library) — shown immediately, then
  /// replaced by a fresh query.
  final List<AssetItem> assets;

  /// The skill key (e.g. `todo`, `external_ref`, or a custom skill name).
  /// Drives both the live re-query and the protected-skill guard.
  final String? skillName;
  const CategoryDetailPage({
    super.key,
    required this.meta,
    required this.assets,
    this.skillName,
  });

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  final _api = ApiClient();
  late List<AssetItem> _assets = widget.assets;

  // Built-in skills that can't be deleted. idea/misc merged into 随记 (notes),
  // so the protected set is {todo, expense, 随记}; system skills
  // (external_ref/qa/contact) never reach here.
  static const _protected = {'todo', 'expense', 'notes'};

  bool get _canDelete =>
      widget.meta.userSkillId != null && !_protected.contains(widget.skillName);

  // Revision-keyed re-fetch driven from build() via ValueListenableBuilder (see
  // LibraryPage) — survives hot-reload, can't miss a data change. Seeds from the
  // snapshot in widget.assets for instant first paint, then the first revision
  // tick schedules a fresh query.
  int _loadedRev = -1;

  void _maybeReload(int rev) {
    if (rev == _loadedRev) return;
    _loadedRev = rev;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _reload() async {
    final skill = widget.skillName;
    if (skill == null) return; // entity buckets use their own pages
    try {
      final res = await _api.getJson('/api/assets', query: {'user_skill_name': skill});
      final list = (res is Map ? res['assets'] : null) as List? ?? const [];
      final items = list
          .whereType<Map>()
          .map((e) => AssetItem.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (mounted) setState(() => _assets = items);
    } catch (_) {
      // keep showing the current list on a transient failure
    }
  }

  Future<void> _confirmDelete() async {
    final eu = context.eu;
    final n = _assets.length;
    final hasAssets = n > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: eu.surfaceRaised,
        title: Text('删除「${widget.meta.label}」？', style: TextStyle(color: eu.textHi)),
        content: Text(
          hasAssets ? '这会同时删除 $n 条记录，且无法恢复。' : '确定删除这个技能？',
          style: TextStyle(color: eu.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: eu.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasAssets ? '仍然删除' : '确定删除',
                style: TextStyle(color: eu.accentRed, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = widget.meta.userSkillId!;
      await _api.deleteJson('/api/skills/$id${hasAssets ? '?force=true' : ''}');
      bumpData();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '删除失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: Text('${widget.meta.icon} ${widget.meta.label}'),
        actions: [
          // 卡片配置:从这里 preview + 调整 icon / 颜色 / 字段位置(render_spec)。
          if (widget.meta.userSkillId != null && widget.skillName != null)
            IconButton(
              tooltip: '卡片配置',
              icon: Icon(Icons.tune, color: eu.textMid),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SkillConfigPage(
                  skillName: widget.skillName!,
                  userSkillId: widget.meta.userSkillId!,
                  label: widget.meta.label,
                ),
              )),
            ),
          if (_canDelete)
            IconButton(
              tooltip: '删除技能',
              icon: Icon(Icons.delete_outline, color: eu.textMid),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: dataRevision,
        builder: (context, rev, _) {
          _maybeReload(rev);
          final isExternal = widget.skillName == 'external_ref';
          final sorted = [..._assets]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          // 外部容器装的是「同步到第三方的引用」——顶部放一个去「已连接应用」的入口,
          // 让用户从"看外部产物"直接跳到"管外部连接"(§4.4.2)。即使空列表也显示。
          if (sorted.isEmpty && !isExternal) {
            return Center(child: Text('还没有记录', style: TextStyle(color: eu.textMid, fontSize: 14)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (isExternal) ...[
                _manageConnectionsCard(eu),
                const SizedBox(height: 14),
              ],
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Center(
                    child: Text(
                      isExternal ? '还没有同步到外部的内容' : '还没有记录',
                      style: TextStyle(color: eu.textMid, fontSize: 14),
                    ),
                  ),
                )
              else
                ..._withDayHeaders(eu, sorted),
            ],
          );
        },
      ),
    );
  }

  // 外部容器顶部的「管理连接」入口卡 → 设置 · 已连接应用(§4.0.6 / §1.7.1)。
  Widget _manageConnectionsCard(EurekaColors eu) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ConnectedAppsPage())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [eu.brand.withValues(alpha: 0.16), eu.brand.withValues(alpha: 0.04)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: eu.brand.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: eu.brand.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: eu.brand.withValues(alpha: 0.30)),
              ),
              child: Icon(Icons.hub_outlined, color: eu.brand, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('管理连接',
                      style: TextStyle(color: eu.textHi, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('连接 / 管理 钉钉、Notion 等外部应用',
                      style: TextStyle(color: eu.textMid, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: eu.brand, size: 20),
          ],
        ),
      ),
    );
  }

  // 按天分隔 (§4.4.2): newest-first list with a light group header at each day
  // boundary (今天 / 昨天 / M月D日). Reuses the 最近/日历 grouping style;
  // visual-only, no sort menu.
  List<Widget> _withDayHeaders(EurekaColors eu, List<AssetItem> items) {
    final out = <Widget>[];
    final now = DateTime.now();
    String? lastKey;
    for (final a in items) {
      final d = DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
      final key = '${d.year}-${d.month}-${d.day}';
      if (key != lastKey) {
        lastKey = key;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(_dayLabel(d, now),
              style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
        ));
      }
      // Tap → detail sheet; left-swipe → delete (handled by SkillCard).
      out.add(SkillCard({
        'user_skill_name': a.skillName,
        'payload': a.payload,
        'asset_id': a.id,
        'session_id': a.sessionId,
        'domain': a.domain,
      }, layoutOverride: 'horizontal'));
    }
    return out;
  }

  String _dayLabel(DateTime d, DateTime now) {
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    final y = now.subtract(const Duration(days: 1));
    final isYesterday = d.year == y.year && d.month == y.month && d.day == y.day;
    return isToday ? '今天' : isYesterday ? '昨天' : '${d.month}月${d.day}日';
  }
}
