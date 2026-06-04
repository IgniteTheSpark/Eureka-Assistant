import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import 'add_skill.dart';
import 'category_detail_page.dart';
import 'entity_list_page.dart';

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
  _LibData(this.assets, this.skills, this.events, this.contacts);

  int get eventCount => events.length;
  int get contactCount => contacts.length;
  int get total => assets.length + eventCount + contactCount;
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

// Registration cap — keep in sync with backend `USER_SKILL_CAP` (api/skills.py).
const _skillCap = 30;

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
    ]);
    return _LibData(
      r[0] as List<AssetItem>,
      r[1] as Map<String, SkillMeta>,
      r[2] as List<Map<String, dynamic>>,
      r[3] as List<Map<String, dynamic>>,
    );
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
                Text('${total ?? '·'} ITEMS · LAST 30D',
                    style: euMono(fontSize: 10.5, letterSpacing: 1.6, color: eu.textLo)),
              ],
            ),
          ),
          IconButton(
              onPressed: _refresh,
              tooltip: '刷新',
              icon: Icon(Icons.refresh, color: eu.textMid)),
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

    final recent = _buildRecent(data)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentTop = recent.take(12).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        const _SectionLabel('常驻 · PERMANENT'),
        const SizedBox(height: 8),
        Row(
          children: [
            _coreTile(eu, '●', '事件', 'purple', data.eventCount,
                () => _openEntity('事件', '/api/events', 'events', 'event')),
            _coreTile(eu, '◯', '名片', 'neutral', data.contactCount,
                () => _openEntity('名片', '/api/contacts', 'contacts', 'contact')),
            _coreTile(eu, '🔗', '外部', 'blue', bySkill['external_ref'] ?? 0, () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CategoryDetailPage(
                  meta: const SkillMeta('🔗', '外部', 'purple'),
                  skillName: 'external_ref',
                  assets: data.assets.where((a) => a.skillName == 'external_ref').toList(),
                ),
              ));
            }),
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
            _addTile(eu, gridSkills.length),
            for (final e in gridSkills)
              _skillTile(eu, e.value, bySkill[e.key] ?? 0, () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CategoryDetailPage(
                    meta: e.value,
                    skillName: e.key,
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

  Widget _coreTile(
      EurekaColors eu, String icon, String label, String accentName, int count, VoidCallback onTap) {
    final accent = _accent(eu, accentName);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
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

  Widget _addTile(EurekaColors eu, int count) {
    final full = count >= _skillCap;
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
                  Text('$count/$_skillCap',
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
