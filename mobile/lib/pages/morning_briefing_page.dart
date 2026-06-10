import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../app_events.dart' show navigatorKey;

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

/// Show today's briefing if it's morning (before 12:00) and we haven't shown it
/// today (SharedPreferences date stamp). Call once from the shell after auth.
/// Failure = silent skip — the morning page must never block app startup.
Future<void> maybeShowMorningBriefing() async {
  if (_mbAttempted) return;
  _mbAttempted = true;
  final now = DateTime.now();
  if (now.hour >= 12) return; // §14.6 中午前
  final prefs = await SharedPreferences.getInstance();
  final today = '${now.year}-${now.month}-${now.day}';
  if (prefs.getString('mb_shown_date') == today) return; // 每天一次
  final api = ApiClient();
  try {
    final res = await api.getJson('/api/briefing/today');
    final report = (res is Map ? res['report'] : null) as Map?;
    final html = report?['html'] as String?;
    if (html == null || html.isEmpty) return;
    await prefs.setString('mb_shown_date', today);
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(PageRouteBuilder(
      fullscreenDialog: true,
      opaque: true,
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1024))
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
          // bottom「开始今天」pill — the design's swipe hint made tappable
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 14,
            child: Center(
              child: GestureDetector(
                onTap: _dismiss,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: const Text('开始今天 →',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
