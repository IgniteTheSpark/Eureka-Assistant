import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../theme/eureka_colors.dart';
import '../widgets/toast.dart';

/// Full-screen report viewer (§6.8.5). Renders the engine's single-file HTML in
/// a locked-down WKWebView: JavaScript is ON and the bundled **GSAP** library is
/// injected into the document head before load, so the report's enhancement
/// script animates with GSAP (it falls back to a vanilla reveal if gsap is
/// absent — e.g. in an exported .html). Navigation to any external URL is
/// blocked — the report is a self-contained, offline document.
///
/// Top bar actions (§6.7):
/// - **换装**: re-render the same content_md with a fresh palette via
///   `POST /api/reports/{id}/rerender` → reload the WebView. No re-query.
/// - **分享**: export the report HTML to the iOS share sheet (.html file).
class ReportViewerPage extends StatefulWidget {
  final String title;
  final String html;

  /// When set, enables 换装 (re-render). Reports opened from a list pass it;
  /// a freshly-generated report passes its new id too.
  final String? reportId;

  const ReportViewerPage({
    super.key,
    required this.title,
    required this.html,
    this.reportId,
  });

  @override
  State<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<ReportViewerPage> {
  final _api = ApiClient();
  late final WebViewController _controller;
  late String _html = widget.html;
  String? _gsap; // bundled gsap.min.js, loaded once
  String? _scrolltrigger; // ScrollTrigger plugin — scroll-scrub image motion (§6.6.2)
  String? _pixel; // pixel.js — pet render engine (§6.6.1 signature band)
  String? _mascot; // mascot.js — Mascot.mount() for the REKA band
  bool _busy = false;

  // §6.13 / handoff Phase 1 — 报告 → 待办. The report's `:::actions` render as a
  // NATIVE「✦ 接下来」bar below the WebView (the in-HTML checklist is read-only).
  // Each row: [+ 待办] → POST /api/reports/{id}/actions (idempotent server-side);
  // already-created rows show「已加 ✓」.
  List<Map<String, dynamic>> _actions = [];
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0E16))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final u = req.url;
          if (u.startsWith('http://') || u.startsWith('https://')) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));
    _bootstrap();
    _loadActions();
  }

  Future<void> _loadActions() async {
    final id = widget.reportId;
    if (id == null) return;
    try {
      final res = await _api.getJson('/api/reports/$id/actions');
      final list = (res is Map ? res['actions'] : null) as List?;
      if (list == null || !mounted) return;
      setState(() => _actions = list.whereType<Map>()
          .map((a) => Map<String, dynamic>.from(a))
          .where((a) => (a['title'] as String?)?.isNotEmpty ?? false)
          .toList());
    } catch (_) {
      // actions bar is an enhancement — a fetch failure just means no bar
    }
  }

  Future<void> _addAction(String title) async {
    final id = widget.reportId;
    if (id == null || _adding.contains(title)) return;
    setState(() => _adding.add(title));
    try {
      final res = await _api.postJson('/api/reports/$id/actions', {'title': title});
      final created = res is Map && res['created'] == true;
      if (!mounted) return;
      setState(() {
        for (final a in _actions) {
          if (a['title'] == title) a['created'] = true;
        }
      });
      showToast(context, created ? '已加入待办 ✓' : '已经在待办里了');
      bumpData(); // 待办列表 / 流页面立刻能看到
    } catch (e) {
      if (mounted) showToast(context, '加待办失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _adding.remove(title));
    }
  }

  Future<void> _addAllActions() async {
    for (final a in List<Map<String, dynamic>>.from(_actions)) {
      if (a['created'] == true) continue;
      await _addAction(a['title'] as String);
    }
  }

  Future<void> _bootstrap() async {
    try {
      _gsap = await rootBundle.loadString('assets/js/gsap.min.js');
    } catch (_) {
      _gsap = null; // missing asset → report falls back to its vanilla reveal
    }
    try {
      _scrolltrigger = await rootBundle.loadString('assets/js/ScrollTrigger.min.js');
    } catch (_) {
      _scrolltrigger = null; // missing → scroll-scrub falls back to non-scrub motion
    }
    try {
      _pixel = await rootBundle.loadString('assets/js/pixel.js');
      _mascot = await rootBundle.loadString('assets/js/mascot.js');
    } catch (_) {
      _pixel = _mascot = null; // missing → signature band shows wordmark only
    }
    await _controller.loadHtmlString(_withEngines(_html));
  }

  /// Splice the bundled engines into the document head so `window.gsap` (animation)
  /// and `window.Mascot` (§6.6.1 REKA band) exist when the report's end-of-body
  /// scripts run (§6.6 "渲染前注入"). Each is independent + optional (graceful).
  String _withEngines(String html) {
    final buf = StringBuffer();
    // gsap MUST precede ScrollTrigger; register the plugin once both are present.
    for (final js in [_gsap, _scrolltrigger, _pixel, _mascot]) {
      if (js != null && js.isNotEmpty) buf.write('<script>$js</script>');
    }
    if ((_gsap?.isNotEmpty ?? false) && (_scrolltrigger?.isNotEmpty ?? false)) {
      buf.write('<script>try{gsap.registerPlugin(ScrollTrigger);}catch(e){}</script>');
    }
    final head = buf.toString();
    if (head.isEmpty) return html;
    if (html.contains('</head>')) return html.replaceFirst('</head>', '$head</head>');
    return head + html;
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _rerender() async {
    final id = widget.reportId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await _api.postJson('/api/reports/$id/rerender', {});
      final report = (res is Map ? res['report'] : null) as Map?;
      final html = report?['html'] as String?;
      if (html != null && html.isNotEmpty) {
        _html = html;
        await _controller.loadHtmlString(_withEngines(html));
        bumpData(); // library list reflects the new palette in spec
      }
    } catch (e) {
      if (mounted) showToast(context, '换装失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final safe = widget.title.replaceAll(RegExp(r'[^\w一-龥]+'), '_');
      final file = File(
          '${Directory.systemTemp.path}/eureka_${safe.isEmpty ? "report" : safe}.html');
      // Self-contained export (§6.6.1): inline the engines + gene so the shared
      // .html animates standalone (GSAP charts + the REKA signature band).
      await file.writeAsString(_withEngines(_html));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/html', name: '${widget.title}.html')],
        subject: widget.title,
      );
    } catch (e) {
      if (mounted) showToast(context, '分享失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 报告查看器是固定深色面(WebView/scaffold 背景硬编码 0xFF0B0E16,报告 HTML
    // 按深色设计)。chrome(appbar + 原生「✦ 接下来」代办 bar)必须用深色主题色,
    // 不能跟随 app 明暗 —— 否则默认浅色模式下 eu.textHi/textLo 变深色文字,压在
    // 深色 bar 上不可读。固定用 EurekaColors.dark,与报告深色面一致。
    final eu = EurekaColors.dark;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E16),
        foregroundColor: eu.textHi,
        elevation: 0,
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (widget.reportId != null)
            IconButton(
              tooltip: '换装',
              icon: const Text('🎨', style: TextStyle(fontSize: 17)),
              onPressed: _busy ? null : _rerender,
            ),
          IconButton(
            tooltip: '分享',
            icon: Icon(Icons.ios_share, color: eu.textMid),
            onPressed: _busy ? null : _share,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_busy)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: eu.brand,
                    ),
                  ),
              ],
            ),
          ),
          if (_actions.isNotEmpty) _actionsBar(eu),
        ],
      ),
    );
  }

  /// §6.13 native「✦ 接下来」action bar — turns the report's suggested actions
  /// into real todos with one tap (provenance: source_report_id, server-side).
  Widget _actionsBar(EurekaColors eu) {
    final pending = _actions.where((a) => a['created'] != true).length;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10141F),
        border: Border(top: BorderSide(color: eu.rule, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 216),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
                child: Row(
                  children: [
                    Text('✦ 接下来',
                        style: TextStyle(
                            color: eu.brand,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5)),
                    const Spacer(),
                    if (pending > 1)
                      TextButton(
                        onPressed: _adding.isEmpty ? _addAllActions : null,
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        child: Text('全部加到待办',
                            style: TextStyle(color: eu.brand, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _actions.length,
                  itemBuilder: (_, i) {
                    final a = _actions[i];
                    final title = a['title'] as String;
                    final created = a['created'] == true;
                    final busy = _adding.contains(title);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                      child: Row(
                        children: [
                          Icon(
                              created
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 16,
                              color: created ? eu.brand : eu.textLo),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: eu.textHi, fontSize: 13.5, height: 1.3)),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 28,
                            child: created
                                ? Text('已加 ✓',
                                    style: TextStyle(
                                        color: eu.textLo, fontSize: 12))
                                : OutlinedButton(
                                    onPressed:
                                        busy ? null : () => _addAction(title),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: eu.brand,
                                      side: BorderSide(
                                          color: eu.brand.withValues(alpha: 0.5)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                    child: Text(busy ? '…' : '+ 待办'),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
