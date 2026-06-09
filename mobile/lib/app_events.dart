import 'dart:async';

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/sse_client.dart';
import 'data_revision.dart';
import 'pages/calendar_page.dart';
import 'pages/report_viewer_page.dart';
import 'pages/session_detail_page.dart';
import 'pet/reka_notifications.dart';
import 'theme/app_theme.dart';

/// True while the hardware flash-memo button is held (SSE `listening` event).
final listeningNotifier = ValueNotifier<bool>(false);

/// Root navigator — lets [AppEvents] push routes + insert the toast overlay.
final navigatorKey = GlobalKey<NavigatorState>();

/// App-level SSE bridge to /api/notifications/stream. Drives the listening
/// overlay (`listening`), live session refresh (`capture`), and the top toast +
/// refresh (`notification`). Auto-reconnects; one connection for the whole app.
class AppEvents {
  AppEvents._();
  static final AppEvents instance = AppEvents._();

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _run();
  }

  Future<void> _run() async {
    while (true) {
      try {
        await for (final ev in getSse('/api/notifications/stream')) {
          _handle(ev);
        }
      } catch (_) {
        // connection dropped — reconnect below
      }
      listeningNotifier.value = false;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  void _handle(SseEvent ev) {
    switch (ev.type) {
      case 'listening':
        final s = ev.json['state'];
        listeningNotifier.value = s == 'on' || s == true;
      case 'capture':
        // Input turn persisted → refresh so the flash session shows it +「正在整理」.
        bumpData();
      case 'notification':
        bumpData();
        _toast(ev.json);
        final j = ev.json;
        final type = j['type'] as String? ?? '';
        RekaNotifications.instance.add(
          icon: type == 'flash_done' ? '⚡' : (type.startsWith('task') ? '⚙️' : '🔔'),
          title: j['title'] as String? ?? '通知',
          meta: j['body'] as String?,
          type: type,                              // carry routing info so the
          link: j['link'] as String? ?? '',        // REKA panel + toast can open it
        );
    }
  }

  void _toast(Map<String, dynamic> j) {
    final nav = navigatorKey.currentState;
    final overlay = nav?.overlay;
    if (overlay == null) return;
    final type = j['type'] as String? ?? '';
    final title = j['title'] as String? ?? '通知';
    final body = j['body'] as String? ?? '';
    final link = j['link'] as String? ?? '';
    final ms = (type == 'task_done' || type == 'task_failed') ? 7500 : 4500;

    late OverlayEntry entry;
    void close() {
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => _TopToast(
        icon: type == 'flash_done' ? '⚡' : (type.startsWith('task') ? '⚙' : '🔔'),
        title: title,
        body: body,
        onTap: link.isEmpty
            ? null
            : () {
                close();
                openNotificationTarget(type, link);
              },
        onClose: close,
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(Duration(milliseconds: ms), close);
  }
}

/// Route a notification (from the toast OR the REKA 通知 panel) to its target.
/// Best-effort + async (report_done fetches html); unknown types no-op.
Future<void> openNotificationTarget(String type, String link) async {
  final nav = navigatorKey.currentState;
  if (nav == null || link.isEmpty) return;

  // reminder link is structured: reminder:evt:<id>:<thr> / reminder:todo:<id>:<thr>
  // — both events and todos live on the calendar timeline.
  if (type == 'reminder' || link.startsWith('reminder:')) {
    nav.push(MaterialPageRoute(builder: (_) => const CalendarPage()));
    return;
  }
  if (type == 'flash_done') {
    nav.push(MaterialPageRoute(
        builder: (_) => SessionDetailPage(sessionId: link, title: '闪念')));
    return;
  }
  if (type == 'report_done') {
    try {
      final api = ApiClient();
      final res = await api.getJson('/api/reports/$link');
      api.close();
      final r = (res is Map ? res['report'] : null) as Map?;
      if (r != null) {
        nav.push(MaterialPageRoute(
          builder: (_) => ReportViewerPage(
            title: r['title'] as String? ?? '报告',
            html: r['html'] as String? ?? '',
            reportId: link,
          ),
        ));
      }
    } catch (_) {/* best-effort — a deleted report just doesn't open */}
    return;
  }
  // task_done / task_failed / unknown → no clean target page; no-op.
}

/// Top-center toast (web Toast parity): themed surface, tappable to follow its
/// deep-link, × to dismiss. Slides in from the top.
class _TopToast extends StatefulWidget {
  final String icon;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final VoidCallback onClose;
  const _TopToast({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -0.4), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _c,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
                decoration: BoxDecoration(
                  color: eu.surfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: eu.border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: eu.brand.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: eu.brand.withValues(alpha: 0.30)),
                      ),
                      child: Text(widget.icon, style: const TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: eu.textHi, fontSize: 13.5, fontWeight: FontWeight.w600)),
                          if (widget.body.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(widget.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: eu.textMid, fontSize: 12, height: 1.35)),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onClose,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 16, color: eu.textLo),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
