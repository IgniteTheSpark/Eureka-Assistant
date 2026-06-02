import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline.dart';
import 'category_detail_page.dart';
import 'notifications_page.dart';

/// Library surface — asset categories grouped by skill, from GET /api/assets
/// (+ /api/skills for icons/labels). Tap a category to list its assets.
/// AddSkillWizard is stubbed for now.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibData {
  final List<AssetItem> assets;
  final Map<String, SkillMeta> skills;
  _LibData(this.assets, this.skills);
}

class _LibraryPageState extends State<LibraryPage> {
  final _api = ApiClient();
  late Future<_LibData> _future = _load();

  Future<_LibData> _load() async {
    final r = await Future.wait([fetchAssets(_api), fetchSkills(_api)]);
    return _LibData(r[0] as List<AssetItem>, r[1] as Map<String, SkillMeta>);
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
                  Text('资产库',
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
              child: FutureBuilder<_LibData>(
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
                  final cats = _group(data.assets);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    children: [
                      if (cats.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(
                              child: Text('还没有资产',
                                  style: TextStyle(color: eu.textMid))),
                        ),
                      for (final c in cats)
                        _CategoryRow(
                          meta: resolveMeta(c.key, data.skills),
                          count: c.value.length,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CategoryDetailPage(
                                meta: resolveMeta(c.key, data.skills),
                                assets: c.value,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _AddSkillButton(onTap: () {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                              const SnackBar(content: Text('添加新技能 · 即将上线')));
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Group assets by skill, most-populated category first.
  List<MapEntry<String, List<AssetItem>>> _group(List<AssetItem> assets) {
    final by = <String, List<AssetItem>>{};
    for (final a in assets) {
      by.putIfAbsent(a.skillName, () => []).add(a);
    }
    return by.entries.toList()
      ..sort((x, y) => y.value.length.compareTo(x.value.length));
  }
}

class _CategoryRow extends StatelessWidget {
  final SkillMeta meta;
  final int count;
  final VoidCallback onTap;
  const _CategoryRow({required this.meta, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final accent = switch (meta.accentColor) {
      'blue' => eu.accentBlue,
      'amber' => eu.accentAmber,
      'green' => eu.accentGreen,
      'red' => eu.accentRed,
      'purple' => eu.accentPurple,
      _ => eu.textMid,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.04)],
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Text(meta.icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(meta.label,
                  style: TextStyle(
                      color: eu.textHi, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$count',
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: eu.textLo, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AddSkillButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSkillButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: eu.border, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Icon(Icons.add, color: eu.textMid, size: 20),
            const SizedBox(width: 12),
            Text('添加新技能',
                style: TextStyle(color: eu.textMid, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
