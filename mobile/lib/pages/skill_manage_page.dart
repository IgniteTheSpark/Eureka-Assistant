import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../widgets/toast.dart';
import 'add_skill.dart';

// Not in the user-toggled active set: system/first-class (external_ref/qa/contact)
// + 常驻 built-ins (待办/随记 are always-on, never toggled, not counted in the cap).
// Mirrors backend `_CAP_EXCLUDED` (api/skills.py).
const _hidden = {'external_ref', 'qa', 'contact', 'todo', 'notes'};

class _SkillRow {
  final String userSkillId;
  final String name; // machine name
  final String displayName;
  final String icon;
  final String accent;
  final bool enabledServer;
  final int count;
  _SkillRow(this.userSkillId, this.name, this.displayName, this.icon, this.accent,
      this.enabledServer, this.count);
}

/// 技能管理页 — list ALL skills (incl. disabled), toggle the active set (capped
/// at `activeCap`), save → PUT /api/skills/active, delete, add new. Saving takes
/// effect on the next agent message (the skill dictionary is re-pulled per request).
class SkillManagePage extends StatefulWidget {
  const SkillManagePage({super.key});

  @override
  State<SkillManagePage> createState() => _SkillManagePageState();
}

class _SkillManagePageState extends State<SkillManagePage> {
  final _api = ApiClient();
  bool _loading = true;
  String? _error;
  int _cap = 9;
  List<_SkillRow> _rows = [];
  final Set<String> _active = {}; // staged active user_skill_ids
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getJson('/api/skills');
      final assetsRes = await _api.getJson('/api/assets');
      if (!mounted) return;
      final counts = <String, int>{};
      for (final a in ((assetsRes is Map ? assetsRes['assets'] : null) as List? ?? const [])) {
        if (a is Map) {
          final n = a['user_skill_name'] as String?;
          if (n != null) counts[n] = (counts[n] ?? 0) + 1;
        }
      }
      final rows = <_SkillRow>[];
      for (final s in ((res is Map ? res['skills'] : null) as List? ?? const [])) {
        if (s is! Map) continue;
        final name = s['name'] as String?;
        if (name == null || _hidden.contains(name)) continue;
        final rs = (s['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
        rows.add(_SkillRow(
          s['user_skill_id'] as String? ?? '',
          name,
          s['display_name'] as String? ?? name,
          rs['icon'] as String? ?? '•',
          rs['accent_color'] as String? ?? 'gray',
          (s['enabled'] as int? ?? 1) != 0,
          counts[name] ?? 0,
        ));
      }
      setState(() {
        _cap = (res is Map ? res['active_cap'] as int? : null) ?? 9;
        _rows = rows;
        _active
          ..clear()
          ..addAll(rows.where((r) => r.enabledServer).map((r) => r.userSkillId));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _toggle(_SkillRow r, bool on) {
    if (on && _active.length >= _cap && !_active.contains(r.userSkillId)) {
      showToast(context, '最多同时激活 $_cap 个技能，请先停用一个', error: true);
      return;
    }
    setState(() {
      if (on) {
        _active.add(r.userSkillId);
      } else {
        _active.remove(r.userSkillId);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _api.putJson('/api/skills/active', {'active_ids': _active.toList()});
      bumpData();
      if (mounted) {
        showToast(context, '已保存');
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, '保存失败：$e', error: true);
      }
    }
  }

  Future<bool> _delete(_SkillRow r) async {
    final eu = context.eu;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: eu.surfaceRaised,
        title: Text('删除「${r.displayName}」？', style: TextStyle(color: eu.textHi)),
        content: Text(
          r.count > 0 ? '这会同时删除 ${r.count} 条记录，且无法恢复。' : '确定删除这个技能？',
          style: TextStyle(color: eu.textMid),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: eu.textMid))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(r.count > 0 ? '仍然删除' : '确定删除',
                  style: TextStyle(color: eu.accentRed, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await _api.deleteJson('/api/skills/${r.userSkillId}${r.count > 0 ? '?force=true' : ''}');
      _active.remove(r.userSkillId);
      bumpData();
      return true;
    } catch (e) {
      if (mounted) showToast(context, '删除失败：$e', error: true);
      return false;
    }
  }

  Color _accentColor(EurekaColors eu, String name) => switch (name) {
        'blue' => eu.accentBlue,
        'amber' => eu.accentAmber,
        'green' => eu.accentGreen,
        'red' => eu.accentRed,
        'purple' => eu.accentPurple,
        _ => eu.textMid,
      };

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final n = _active.length;
    final full = n >= _cap;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: const Text('技能管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text('活跃 $n/$_cap',
                  style: euMono(
                      fontSize: 12,
                      color: full ? eu.accentRed : eu.brand,
                      letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('加载失败：$_error',
                        textAlign: TextAlign.center, style: TextStyle(color: eu.accentRed)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text('打开的技能进资产库 + 被 Agent 自动记录；关闭的只是收起，历史记录不删、仍可查。左滑删除。',
                          style: TextStyle(color: eu.textLo, fontSize: 11.5, height: 1.4)),
                    ),
                    for (final r in _rows) _row(eu, r),
                    const SizedBox(height: 12),
                    _addBtn(eu),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                // Fixed height — a bare alignment-Container in bottomNavigationBar
                // gets unbounded height and expands to fill the screen.
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    behavior: HitTestBehavior.opaque,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: eu.brand, borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('保存',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _row(EurekaColors eu, _SkillRow r) {
    final accent = _accentColor(eu, r.accent);
    final on = _active.contains(r.userSkillId);
    return Dismissible(
      key: ValueKey('skill_${r.userSkillId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: eu.accentRed.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _delete(r),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Text(r.icon, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${r.count} 条记录',
                      style: euMono(fontSize: 10.5, color: eu.textLo)),
                ],
              ),
            ),
            Switch(
              value: on,
              activeThumbColor: eu.brand,
              onChanged: (v) => _toggle(r, v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addBtn(EurekaColors eu) {
    return GestureDetector(
      onTap: () => showAddSkill(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: eu.brand.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✨', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text('新技能',
                style: TextStyle(color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
