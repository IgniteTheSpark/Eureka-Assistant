import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline.dart';

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

  // The five built-in free-text skills can't be deleted (mirrors the web
  // protected set); system skills (external_ref/qa/contact) never reach here.
  static const _protected = {'todo', 'idea', 'expense', 'notes', 'misc'};

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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('删除失败：$e')));
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
          final sorted = [..._assets]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return sorted.isEmpty
              ? Center(child: Text('还没有记录', style: TextStyle(color: eu.textMid, fontSize: 14)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    final a = sorted[i];
                    // Tap → detail sheet; left-swipe → delete (handled by SkillCard).
                    return SkillCard({
                      'user_skill_name': a.skillName,
                      'payload': a.payload,
                      'asset_id': a.id,
                      'session_id': a.sessionId,
                    }, layoutOverride: 'horizontal');
                  },
                );
        },
      ),
    );
  }
}
