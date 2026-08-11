import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../theme/eureka_colors.dart';
import '../theme_v2/report/report_actions.dart';
import '../widgets/toast.dart';

/// Theme V2 HTML owns its palette and color-scheme. Retained as a compatibility
/// seam for older callers, but intentionally does not mutate report CSS.
String applyThemeV2ReportViewerTheme(String html, {String? palette}) => html;

final _trustedReadyIllustrationSlot = RegExp(
  r'<figure id="reka-report-illustration" class="r-illustration" '
  r'data-illustration-status="ready"><img src="/api/files/[A-Za-z0-9_-]+" '
  r'alt="报告插图" loading="lazy"></figure>',
);

String? extractTrustedReportIllustrationSlot(String html) {
  final matches = _trustedReadyIllustrationSlot.allMatches(html).toList();
  return matches.length == 1 ? matches.single.group(0) : null;
}

@immutable
class ReportViewerChromePalette {
  const ReportViewerChromePalette({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
  });

  final Color background;
  final Color foreground;
  final Color muted;
  final Color accent;
}

/// Mirrors the immutable CSS palette owned by the Theme V2 report renderer.
/// Keeping native chrome on the same exact tokens avoids a visible seam between
/// the AppBar and the HTML document.
ReportViewerChromePalette reportViewerChromePalette(String? palette) =>
    switch (palette) {
      'pal-dashboard' => const ReportViewerChromePalette(
        background: Color(0xFF0C1118),
        foreground: Color(0xFFEAF1FB),
        muted: Color.fromRGBO(200, 215, 235, 0.58),
        accent: Color(0xFF4F8CFF),
      ),
      'pal-neon' => const ReportViewerChromePalette(
        background: Color(0xFF06070F),
        foreground: Color(0xFFF4F0FF),
        muted: Color.fromRGBO(200, 194, 240, 0.58),
        accent: Color(0xFFA06BFF),
      ),
      'pal-ink' => const ReportViewerChromePalette(
        background: Color(0xFF14130F),
        foreground: Color(0xFFF6F1E6),
        muted: Color.fromRGBO(228, 220, 200, 0.60),
        accent: Color(0xFFD98A4B),
      ),
      'pal-minimal' => const ReportViewerChromePalette(
        background: Color(0xFFF6F5F1),
        foreground: Color(0xFF1A1813),
        muted: Color.fromRGBO(26, 24, 19, 0.56),
        accent: Color(0xFF2F63D6),
      ),
      'pal-warm' => const ReportViewerChromePalette(
        background: Color(0xFFF3ECE0),
        foreground: Color(0xFF2A2015),
        muted: Color.fromRGBO(70, 54, 34, 0.58),
        accent: Color(0xFFC9722E),
      ),
      'pal-forest' => const ReportViewerChromePalette(
        background: Color(0xFF0C1410),
        foreground: Color(0xFFEEF6EF),
        muted: Color.fromRGBO(195, 220, 200, 0.58),
        accent: Color(0xFF4FB37A),
      ),
      _ => const ReportViewerChromePalette(
        background: Color(0xFF0B1220),
        foreground: Color(0xFFF3F6FB),
        muted: Color.fromRGBO(255, 255, 255, 0.62),
        accent: Color(0xFF6F9EFF),
      ),
    };

bool isExternalReportUrl(String raw) {
  final uri = Uri.tryParse(raw);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}

Future<bool> openExternalReportUrl(
  String raw, {
  Future<bool> Function(Uri)? launcher,
}) async {
  if (!isExternalReportUrl(raw)) return false;
  final uri = Uri.parse(raw);
  if (launcher != null) return launcher(uri);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Full-screen report viewer (§6.8.5). Renders the engine's single-file HTML in
/// a locked-down WKWebView: JavaScript is ON and the bundled **GSAP** library is
/// injected into the document head before load, so the report's enhancement
/// script animates with GSAP (it falls back to a vanilla reveal if gsap is
/// absent — e.g. in an exported .html). Qualified HTTP(S) citations open in
/// the system browser; the report WebView itself remains self-contained.
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

  /// Legacy reports expose server-side action extraction and palette rerender.
  /// Theme V2 reports use the immutable report contract and disable both calls.
  final bool enableLegacyEnhancements;
  final bool enableThemeV2Actions;
  final String? themeV2Palette;
  final ApiClient? api;
  final Future<bool> Function(Uri)? externalLinkLauncher;
  final String initialIllustrationStatus;
  final int initialRevision;

  const ReportViewerPage({
    super.key,
    required this.title,
    required this.html,
    this.reportId,
    this.enableLegacyEnhancements = true,
    this.enableThemeV2Actions = false,
    this.themeV2Palette,
    this.api,
    this.externalLinkLauncher,
    this.initialIllustrationStatus = 'not_required',
    this.initialRevision = 1,
  });

  @override
  State<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<ReportViewerPage>
    with WidgetsBindingObserver {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final bool _ownsApi = widget.api == null;
  late final ReportActionsController _actionsController =
      ReportActionsController(api: _api, onTodoCreated: bumpData);
  late final WebViewController _controller;
  late String _html = widget.html;
  String? _gsap; // bundled gsap.min.js, loaded once
  String?
  _scrolltrigger; // ScrollTrigger plugin — scroll-scrub image motion (§6.6.2)
  String? _pixel; // pixel.js — pet render engine (§6.6.1 signature band)
  String? _mascot; // mascot.js — Mascot.mount() for the REKA band
  bool _busy = false;
  Timer? _illustrationPoll;
  bool _illustrationPollInFlight = false;
  bool _viewerVisible = true;
  late String _illustrationStatus = widget.initialIllustrationStatus;
  late int _revision = widget.initialRevision;

  bool get _lightReport =>
      const {'pal-minimal', 'pal-warm'}.contains(widget.themeV2Palette);

  ReportViewerChromePalette get _chrome =>
      reportViewerChromePalette(widget.themeV2Palette);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_chrome.background)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _handleNavigationRequest),
      );
    _bootstrap();
    final id = widget.reportId;
    if (widget.enableThemeV2Actions && id != null) {
      _actionsController.load(id);
    }
  }

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    if (!isExternalReportUrl(request.url)) {
      return NavigationDecision.navigate;
    }
    try {
      final opened = await openExternalReportUrl(
        request.url,
        launcher: widget.externalLinkLauncher,
      );
      if (!opened && mounted) {
        showToast(context, '无法打开该链接', error: true);
      }
    } catch (_) {
      if (mounted) showToast(context, '无法打开该链接', error: true);
    }
    return NavigationDecision.prevent;
  }

  Future<void> _bootstrap() async {
    if (!widget.enableLegacyEnhancements) {
      await _controller.loadHtmlString(_html);
      _scheduleIllustrationPoll();
      return;
    }
    try {
      _gsap = await rootBundle.loadString('assets/js/gsap.min.js');
    } catch (_) {
      _gsap = null; // missing asset → report falls back to its vanilla reveal
    }
    try {
      _scrolltrigger = await rootBundle.loadString(
        'assets/js/ScrollTrigger.min.js',
      );
    } catch (_) {
      _scrolltrigger =
          null; // missing → scroll-scrub falls back to non-scrub motion
    }
    try {
      _pixel = await rootBundle.loadString('assets/js/pixel.js');
      _mascot = await rootBundle.loadString('assets/js/mascot.js');
    } catch (_) {
      _pixel = _mascot = null; // missing → signature band shows wordmark only
    }
    await _controller.loadHtmlString(_withEngines(_html));
    _scheduleIllustrationPoll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _viewerVisible = state == AppLifecycleState.resumed;
    if (!_viewerVisible) {
      _illustrationPoll?.cancel();
      return;
    }
    if (_illustrationStatus == 'pending') {
      unawaited(_refreshIllustration());
    }
  }

  void _scheduleIllustrationPoll() {
    _illustrationPoll?.cancel();
    if (!mounted ||
        !_viewerVisible ||
        !widget.enableThemeV2Actions ||
        widget.reportId == null ||
        _illustrationStatus != 'pending') {
      return;
    }
    _illustrationPoll = Timer(const Duration(seconds: 3), _refreshIllustration);
  }

  Future<void> _refreshIllustration() async {
    final reportId = widget.reportId;
    if (!mounted ||
        !_viewerVisible ||
        reportId == null ||
        _illustrationStatus != 'pending' ||
        _illustrationPollInFlight) {
      return;
    }
    _illustrationPollInFlight = true;
    try {
      final response = await _api.getJson('/api/reports/$reportId');
      if (response is! Map) return;
      final nextRevision = (response['revision'] as num?)?.toInt() ?? _revision;
      final nextStatus =
          response['illustration_status']?.toString() ?? _illustrationStatus;
      if (nextRevision <= _revision && nextStatus == _illustrationStatus) {
        return;
      }
      final nextHtml = response['html']?.toString() ?? '';
      if (nextHtml.isEmpty) return;
      if (nextStatus == 'ready' || nextStatus == 'failed') {
        final patched = await _patchIllustrationSlot(nextHtml, nextStatus);
        if (!patched) await _reloadPreservingScroll(nextHtml);
        _html = nextHtml;
        _revision = nextRevision;
        _illustrationStatus = nextStatus;
      }
    } catch (_) {
      // Keep the readable report open; the next bounded poll retries.
    } finally {
      _illustrationPollInFlight = false;
      _scheduleIllustrationPoll();
    }
  }

  Future<bool> _patchIllustrationSlot(String html, String status) async {
    final slot = extractTrustedReportIllustrationSlot(html);
    final String? script;
    if (status == 'ready' && slot != null) {
      script =
          '''(() => {
          const current = document.getElementById('reka-report-illustration');
          if (!current) return false;
          const template = document.createElement('template');
          template.innerHTML = ${jsonEncode(slot)};
          const replacement = template.content.firstElementChild;
          if (!replacement || replacement.id !== 'reka-report-illustration') return false;
          current.replaceWith(replacement);
          return true;
        })()''';
    } else if (status == 'failed') {
      script = '''(() => {
          const current = document.getElementById('reka-report-illustration');
          if (!current) return false;
          current.remove();
          return true;
        })()''';
    } else {
      script = null;
    }
    if (script == null) return false;
    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      return result == true || result.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _reloadPreservingScroll(String html) async {
    var scrollY = 0.0;
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        'Number(window.scrollY || 0)',
      );
      scrollY = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    } catch (_) {
      scrollY = 0;
    }
    await _controller.loadHtmlString(_withEngines(html));
    await _controller.runJavaScript('window.scrollTo(0, ${scrollY.round()})');
  }

  /// Splice the bundled engines into the document head so `window.gsap` (animation)
  /// and `window.Mascot` (§6.6.1 REKA band) exist when the report's end-of-body
  /// scripts run (§6.6 "渲染前注入"). Each is independent + optional (graceful).
  String _withEngines(String html) {
    if (!widget.enableLegacyEnhancements) return html;
    final buf = StringBuffer();
    // gsap MUST precede ScrollTrigger; register the plugin once both are present.
    for (final js in [_gsap, _scrolltrigger, _pixel, _mascot]) {
      if (js != null && js.isNotEmpty) buf.write('<script>$js</script>');
    }
    if ((_gsap?.isNotEmpty ?? false) && (_scrolltrigger?.isNotEmpty ?? false)) {
      buf.write(
        '<script>try{gsap.registerPlugin(ScrollTrigger);}catch(e){}</script>',
      );
    }
    final head = buf.toString();
    if (head.isEmpty) return html;
    if (html.contains('</head>')) {
      return html.replaceFirst('</head>', '$head</head>');
    }
    return head + html;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _illustrationPoll?.cancel();
    _actionsController.dispose();
    if (_ownsApi) _api.close();
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
        '${Directory.systemTemp.path}/eureka_${safe.isEmpty ? "report" : safe}.html',
      );
      // Self-contained export (§6.6.1): inline the engines + gene so the shared
      // .html animates standalone (GSAP charts + the REKA signature band).
      await file.writeAsString(_withEngines(_html));
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/html', name: '${widget.title}.html'),
      ], subject: widget.title);
    } catch (e) {
      if (mounted) showToast(context, '分享失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = _lightReport ? EurekaColors.light : EurekaColors.dark;
    final chrome = _chrome;
    final reportId = widget.reportId;
    return Scaffold(
      backgroundColor: chrome.background,
      appBar: AppBar(
        backgroundColor: chrome.background,
        foregroundColor: chrome.foreground,
        elevation: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (widget.reportId != null && widget.enableLegacyEnhancements)
            IconButton(
              tooltip: '换装',
              icon: const Text('🎨', style: TextStyle(fontSize: 17)),
              onPressed: _busy ? null : _rerender,
            ),
          IconButton(
            tooltip: '分享',
            icon: Icon(Icons.ios_share, color: chrome.muted),
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
                      color: chrome.accent,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.enableThemeV2Actions && reportId != null)
            ReportActionsTray(
              reportId: reportId,
              controller: _actionsController,
              colors: eu,
            ),
        ],
      ),
    );
  }
}
