import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import 'category_detail_page.dart';
import 'notifications_page.dart';

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
  final int eventCount;
  final int contactCount;
  final int fileCount;
  _LibData(this.assets, this.skills, this.eventCount, this.contactCount, this.fileCount);

  int get total => assets.length + eventCount + contactCount + fileCount;
}

// Skills never shown in the SKILLS grid (system / first-class).
const _hiddenSkills = {'external_ref', 'qa', 'contact'};

class _LibraryPageState extends State<LibraryPage> {
  final _api = ApiClient();
  late Future<_LibData> _future = _load();

  Future<_LibData> _load() async {
    final r = await Future.wait([
      fetchAssets(_api),
      fetchSkills(_api),
      _count('/api/events', 'events'),
      _count('/api/contacts', 'contacts'),
      _count('/api/files', 'files'),
    ]);
    return _LibData(
      r[0] as List<AssetItem>,
      r[1] as Map<String, SkillMeta>,
      r[2] as int,
      r[3] as int,
      r[4] as int,
    );
  }

  Future<int> _count(String path, String key) async {
    try {
      final res = await _api.getJson(path);
      return ((res is Map ? res[key] : null) as List?)?.length ?? 0;
    } catch (_) {
      return 0;
    }
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
        child: FutureBuilder<_LibData>(
          future: _future,
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
                Text('${total ?? '·'} ITEMS · LAST 30D',
                    style: euMono(fontSize: 10.5, letterSpacing: 1.6, color: eu.textLo)),
              ],
            ),
          ),
          IconButton(
              onPressed: _refresh,
              tooltip: '刷新',
              icon: Icon(Icons.refresh, color: eu.textMid)),
          const NotificationsBell(),
        ],
      ),
    );
  }

  Widget _body(EurekaColors eu, _LibData data) {
    final bySkill = <String, int>{};
    for (final a in data.assets) {
      bySkill[a.skillName] = (bySkill[a.skillName] ?? 0) + 1;
    }
    final gridSkills = data.skills.entries
        .where((e) => !_hiddenSkills.contains(e.key))
        .toList();

    final recent = [...data.assets]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentTop = recent.take(8).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        const _SectionLabel('常驻 · PERMANENT'),
        const SizedBox(height: 8),
        Row(
          children: [
            _coreTile(eu, '●', '事件', 'purple', data.eventCount),
            _coreTile(eu, '◯', '名片', 'neutral', data.contactCount),
            _coreTile(eu, '♪', '文件', 'blue', data.fileCount),
            _coreTile(eu, '🔗', '外部', 'blue', bySkill['external_ref'] ?? 0),
          ],
        ),
        const SizedBox(height: 18),
        const _SectionLabel('启用的技能 · SKILLS'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            _addTile(eu),
            for (final e in gridSkills)
              _skillTile(eu, e.value, bySkill[e.key] ?? 0, () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CategoryDetailPage(
                    meta: e.value,
                    assets: data.assets.where((a) => a.skillName == e.key).toList(),
                  ),
                ));
              }),
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

  List<Widget> _recentByDay(List<AssetItem> items) {
    final out = <Widget>[];
    final now = DateTime.now();
    String? lastKey;
    for (final a in items) {
      final d = DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
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
      out.add(SkillCard({
        'user_skill_name': a.skillName,
        'payload': a.payload,
        'asset_id': a.id,
      }));
    }
    return out;
  }

  Widget _coreTile(EurekaColors eu, String icon, String label, String accentName, int count) {
    final accent = _accent(eu, accentName);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.10), eu.surfaceRaised],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: eu.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Text(icon, style: TextStyle(fontSize: 13, color: accent)),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(color: eu.textHi, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('$count', style: euMono(fontSize: 13, color: eu.textLo)),
          ],
        ),
      ),
    );
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

  Widget _addTile(EurekaColors eu) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('添加新技能 · 即将上线')));
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: eu.border),
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
              children: [
                Expanded(
                  child: Text('新技能',
                      style: TextStyle(
                          color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.add, size: 16, color: eu.textMid),
              ],
            ),
          ],
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
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Row(
      children: [
        Text(text, style: euMono(fontSize: 10.5, letterSpacing: 2.2, color: eu.textMid)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: eu.rule)),
      ],
    );
  }
}
