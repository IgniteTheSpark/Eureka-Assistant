import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../app_events.dart' show navigatorKey;
import '../pet/floating_mascot.dart' show mascotSuppressed, releaseMascotSuppress;

/// §14.6 晨间简报 — the immersive「早安」moment. Shown ONCE per day, on the
/// first app open before noon; afterwards the same report lives in the report
/// container like a diary entry (一个产物、两个面).
///
/// 别变负担 (§14.6): one tap and you're in the app — a translucent ✕ and a
/// bottom「开始今天」pill both dismiss; nothing blocks, nothing nags.
class MorningBriefingPage extends StatefulWidget {
  final String html;
  const MorningBriefingPage({super.key, required this.html});

  @override
  State<MorningBriefingPage> createState() => _MorningBriefingPageState();
}

bool _mbAttempted = false; // per-launch guard against concurrent rebuild races

/// DEBUG affordance (默认 false = 正式行为「中午前、每天一次」): true = 跳过
/// 两道门槛,每次 hot-restart 都进沉浸页,且 refresh=1 按当前数据现重建。
const bool _kDebugAlwaysShowMorning = false;

/// Show today's briefing if it's morning (before 12:00) and we haven't shown it
/// today (SharedPreferences date stamp). Call once from the shell after auth.
/// Failure = silent skip — the morning page must never block app startup.
Future<void> maybeShowMorningBriefing() async {
  if (_mbAttempted) return;
  _mbAttempted = true;
  final now = DateTime.now();
  if (!_kDebugAlwaysShowMorning && now.hour >= 12) return; // §14.6 中午前
  final prefs = await SharedPreferences.getInstance();
  final today = '${now.year}-${now.month}-${now.day}';
  if (!_kDebugAlwaysShowMorning && prefs.getString('mb_shown_date') == today) {
    return; // 每天一次
  }
  final api = ApiClient();
  try {
    final res = await api.getJson(
        '/api/briefing/today${_kDebugAlwaysShowMorning ? '?refresh=1' : ''}');
    final report = (res is Map ? res['report'] : null) as Map?;
    final html = report?['html'] as String?;
    if (html == null || html.isEmpty) return;
    await prefs.setString('mb_shown_date', today);
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(PageRouteBuilder(
      fullscreenDialog: true,
      // NOT opaque: an opaque route offstages the shell below (layout skipped),
      // which broke the calendar's jump-to-today while the briefing covered it.
      // Our Scaffold paints a full background anyway, so nothing shows through.
      opaque: false,
      pageBuilder: (context, anim, secondary) => MorningBriefingPage(html: html),
      transitionsBuilder: (context, anim, secondary, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 420),
    ));
  } catch (_) {
    // offline / 401 / server hiccup → just start the normal day
  } finally {
    api.close();
  }
}

class _MorningBriefingPageState extends State<MorningBriefingPage> {
  late final WebViewController _controller;

  bool _didSuppress = false;

  @override
  void initState() {
    super.initState();
    // 沉浸页是 REKA 自己的时刻(hero 里已有它)——隐藏全局浮动球。Mutating a
    // Listenable here runs inside the route's first build pass → "setState()
    // called during build" (same trap pet_page.dart documents); defer a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      mascotSuppressed.value++;
      _didSuppress = true;
    });
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1024))
      // 「向上滑,开始今天」做成真手势:页面滑到底后继续上滑 → 关闭(JS channel);
      // 页内的 .mb-swipe 提示区点一下也关。
      ..addJavaScriptChannel('MBDismiss', onMessageReceived: (_) => _dismiss())
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _controller.runJavaScript(_swipeJs),
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

  @override
  void dispose() {
    // dispose runs while the tree is LOCKED (route teardown) — notifying
    // mascotSuppressed here throws "markNeedsBuild called when widget tree was
    // locked" AND leaves the ball stuck hidden. Defer the release a frame.
    if (_didSuppress) {
      WidgetsBinding.instance.addPostFrameCallback((_) => releaseMascotSuppress());
    }
    super.dispose();
  }

  static const _swipeJs = '''
(function(){
  if (window.__mbSwipe) return; window.__mbSwipe = true;
  var startY = null;
  function atBottom(){
    var y = window.scrollY || document.documentElement.scrollTop || 0;
    return (window.innerHeight + y) >= (document.documentElement.scrollHeight - 6);
  }
  document.addEventListener('touchstart', function(e){
    startY = e.touches && e.touches[0] ? e.touches[0].clientY : null;
  }, {passive:true});
  document.addEventListener('touchend', function(e){
    if (startY == null) return;
    var t = e.changedTouches && e.changedTouches[0];
    var dy = t ? (startY - t.clientY) : 0;
    startY = null;
    if (dy > 70 && atBottom()) { try { MBDismiss.postMessage('1'); } catch(_){} }
  }, {passive:true});
  var sw = document.querySelector('.mb-swipe');
  if (sw) sw.addEventListener('click', function(){ try { MBDismiss.postMessage('1'); } catch(_){} });
})();
''';

  Future<void> _bootstrap() async {
    // pixel + mascot engines → the hero/sign REKA renders the user's real pet.
    final buf = StringBuffer();
    for (final asset in ['assets/js/pixel.js', 'assets/js/mascot.js']) {
      try {
        buf.write('<script>${await rootBundle.loadString(asset)}</script>');
      } catch (_) {/* missing engine → pet slots stay empty, page still fine */}
    }
    var html = widget.html;
    final head = buf.toString();
    if (head.isNotEmpty && html.contains('</head>')) {
      html = html.replaceFirst('</head>', '$head</head>');
    }
    await _controller.loadHtmlString(html);
  }

  void _dismiss() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1024),
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          // translucent ✕ — always reachable, never traps (§14.6 绝不困住人)
          Positioned(
            top: topPad + 8,
            right: 12,
            child: GestureDetector(
              onTap: _dismiss,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.close, size: 18, color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
