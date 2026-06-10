import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../pet/floating_mascot.dart' show openRekaInsight;
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import 'report_viewer_page.dart';

/// 报告容器 (§6.8.4) — the permanent home for synthesis reports, reached from
/// the 资产库 常驻 grid. A prominent「✨ 洞察 · 升华」CTA opens the wizard; below
/// is the list of past reports (tap → WebView viewer, swipe-left → delete).
class ReportListPage extends StatefulWidget {
  const ReportListPage({super.key});

  @override
  State<ReportListPage> createState() => _ReportListPageState();
}

const _genreMeta = {
  'data-report': ('📊', '数据复盘'),
  'idea-synthesis': ('💡', '灵感综合'),
  'proposal': ('📝', '提案'),
  'digest': ('🗞', '概览'),
  'briefing': ('🔎', '调研简报'), // §14.5 会前调研/外部调研(web-search)
};

class _ReportListPageState extends State<ReportListPage> {
  final _api = ApiClient();
  int _loadedRev = -1;
  Future<List<Map<String, dynamic>>>? _future;

  Future<List<Map<String, dynamic>>> _futureFor(int rev) {
    if (rev != _loadedRev || _future == null) {
      _loadedRev = rev;
      _future = _load();
    }
    return _future!;
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final res = await _api.getJson('/api/reports');
      final list = (res is Map ? res['reports'] : null) as List? ?? const [];
      return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _openReport(String? id) async {
    if (id == null) return;
    try {
      final res = await _api.getJson('/api/reports/$id');
      final report = (res is Map ? res['report'] : null) as Map?;
      if (report == null || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: report['title'] as String? ?? '报告',
          html: report['html'] as String? ?? '',
          reportId: report['id'] as String?,
        ),
      ));
    } catch (_) {/* transient — ignore */}
  }

  Future<bool> _deleteReport(String? id) async {
    if (id == null) return false;
    try {
      await _api.deleteJson('/api/reports/$id');
      bumpData();
      return true;
    } catch (_) {
      return false;
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
        title: const Text('报告'),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: dataRevision,
        builder: (context, rev, _) => FutureBuilder<List<Map<String, dynamic>>>(
          future: _futureFor(rev),
          builder: (ctx, snap) {
            final reports = snap.data ?? const [];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                _cta(eu),
                const SizedBox(height: 18),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (reports.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text('还没有报告 —— 点上面「✨ 洞察 · 升华」生成一份',
                        style: euMono(fontSize: 11.5, color: eu.textLo)),
                  )
                else ...[
                  _sectionLabel(eu,'历史 · ${reports.length}'),
                  const SizedBox(height: 8),
                  for (final r in reports) _reportRow(eu, r),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cta(EurekaColors eu) {
    return GestureDetector(
      // Closed loop: funnel through the SAME REKA 洞察 bubble as the radial menu
      // (single-card state machine), not a separate full page.
      onTap: openRekaInsight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [eu.brand.withValues(alpha: 0.22), eu.accentPurple.withValues(alpha: 0.06)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: eu.brand.withValues(alpha: 0.34)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: eu.brand.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: eu.brand.withValues(alpha: 0.34)),
              ),
              child: const Text('✨', style: TextStyle(fontSize: 21)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('洞察 · 升华',
                      style: TextStyle(color: eu.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('把你的记录合成图文报告',
                      style: TextStyle(color: eu.textMid, fontSize: 12.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: eu.brand, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _reportRow(EurekaColors eu, Map<String, dynamic> r) {
    final genre = r['genre'] as String? ?? 'digest';
    final meta = _genreMeta[genre] ?? ('🗞', '报告');
    final created = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
    final dateStr = created == null ? '' : '${created.month}月${created.day}日';
    final id = r['id'] as String?;
    return Dismissible(
      key: ValueKey('report-$id'),
      direction: id == null ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) => _deleteReport(id),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          color: eu.accentRed.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: eu.accentRed),
      ),
      child: GestureDetector(
        onTap: () => _openReport(id),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: eu.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: eu.border),
          ),
          child: Row(
            children: [
              Text(meta.$1, style: const TextStyle(fontSize: 17)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['title'] as String? ?? '报告',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${meta.$2}${dateStr.isEmpty ? '' : ' · $dateStr'}',
                        style: TextStyle(color: eu.textLo, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: eu.textLo),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(EurekaColors eu, String t) =>
      Text(t, style: euMono(fontSize: 10.5, letterSpacing: 2.2, color: eu.textMid));
}
