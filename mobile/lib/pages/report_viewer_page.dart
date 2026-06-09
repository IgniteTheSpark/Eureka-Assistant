import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../theme/app_theme.dart';
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
    final eu = context.eu;
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
      body: Stack(
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
    );
  }
}
