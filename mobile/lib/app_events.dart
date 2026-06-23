import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_client.dart';
import 'api/sse_client.dart';
import 'ble_flash/flash_file_status_controller.dart';
import 'ble_flash/flash_file_workflow.dart';
import 'data_revision.dart';
import 'flash/flash_processing_state.dart';
import 'pages/calendar_page.dart';
import 'pages/report_viewer_page.dart';
import 'pages/session_detail_page.dart';
import 'pet/reka_notifications.dart';
import 'pet/reka_nudges.dart';
import 'render/asset_detail_sheet.dart';
import 'render/render_spec.dart';
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
  static const _flashLogTag = '[FlashFile]';

  bool _started = false;
  int _runId = 0;
  http.Client? _client;

  void _flashLog(String message) => debugPrint('$_flashLogTag SSE $message');

  void start() {
    if (_started) return;
    _started = true;
    final runId = ++_runId;
    _flashLog('app events start');
    _run(runId);
    // §14.7: restore today's un-acted nudges → quiet「...」chip on the ball.
    RekaNudges.instance.loadPending();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _runId++;
    listeningNotifier.value = false;
    _client?.close();
    _client = null;
  }

  Future<void> _run(int runId) async {
    while (_started && runId == _runId) {
      final client = http.Client();
      _client = client;
      try {
        await for (final ev in getSse(
          '/api/notifications/stream',
          client: client,
        )) {
          if (!_started || runId != _runId) break;
          _handle(ev);
        }
      } catch (e) {
        // connection dropped — reconnect below
        _flashLog('SSE disconnected error=$e');
      } finally {
        if (identical(_client, client)) _client = null;
        client.close();
      }
      listeningNotifier.value = false;
      if (!_started || runId != _runId) break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  void _handle(SseEvent ev) {
    switch (ev.type) {
      case 'listening':
        final s = ev.json['state'];
        _flashLog('listening state=$s');
        listeningNotifier.value = s == 'on' || s == true;
      case 'capture':
        // Input turn persisted → refresh so the flash session shows it +「正在整理」.
        _flashLog('capture event session=${ev.json['session_id']}');
        FlashProcessingStatus.instance.applyCapture(ev.json);
        bumpData();
      case 'flash_file_status':
        _flashLog(
          'flash_file_status recording=${ev.json['recording_id']} '
          'clientTask=${ev.json['client_task_id']} status=${ev.json['status']} '
          'file=${ev.json['device_file_name']} message=${ev.json['message']}',
        );
        FlashProcessingStatus.instance.applyFlashStatus(ev.json);
        FlashFileStatusController.instance.applyServerStatus(ev.json);
        FlashFileWorkflow.instance.applyServerStatus(ev.json);
        bumpData();
      case 'notification':
        bumpData();
        final j = ev.json;
        final type = j['type'] as String? ?? '';
        // §14.7 nudge = 拍肩, not an alert: it surfaces as a REKA peek bubble
        // (light bob) handled by the FloatingMascot — NOT the standard toast.
        if (type == 'nudge') {
          final link = (j['link'] as String? ?? '').split(
            ':',
          ); // nudge:<id>:<ref>
          final title = j['title'] as String? ?? '';
          final n = RekaNudge(
            id: link.length > 1 ? link[1] : '',
            text: title,
            body: j['body'] as String? ?? '',
            ref: link.length > 2 ? link.sublist(2).join(':') : '',
            // optimistic guess for the first paint (offer titles carry ✨/📝);
            // refresh() below replaces it with the server's authoritative cta.
            cta: (title.startsWith('✨') || title.startsWith('📝'))
                ? 'synthesize'
                : 'log',
          );
          if (n.id.isNotEmpty && n.text.isNotEmpty) {
            RekaNudges.instance.pushArrival(n);
            RekaNudges.instance.refresh(peekId: n.id);
          }
          RekaNotifications.instance.add(
            id: j['id'] as String? ?? '',
            icon: RekaNotifications.iconFor(type),
            title: j['title'] as String? ?? '提醒',
            meta: j['body'] as String?,
            type: type,
            link: j['link'] as String? ?? '',
          );
          return;
        }
        if (type != 'flash_done') {
          _toast(j);
        }
        RekaNotifications.instance.add(
          id: j['id'] as String? ?? '',
          icon: RekaNotifications.iconFor(type),
          title: j['title'] as String? ?? '通知',
          meta: j['body'] as String?,
          type: type, // carry routing info so the
          link: j['link'] as String? ?? '', // REKA panel + toast can open it
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
        icon: type == 'flash_done'
            ? '⚡'
            : (type.startsWith('task') ? '⚙' : '🔔'),
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

  // §14.7 nudge from the feed → re-open its peek bubble on the ball (if still
  // pending today); a handled/expired one just does nothing (history entry).
  if (type == 'nudge' || link.startsWith('nudge:')) {
    final parts = link.split(':');
    if (parts.length > 1) RekaNudges.instance.reopen(parts[1]);
    return;
  }

  // reminder link is structured: reminder:evt:<id>:<thr> / reminder:todo:<id>:<thr>
  // (UUIDs have no ':'). Open the specific event/todo CARD directly — same as the
  // notifications page — instead of dumping the user on the bare calendar.
  if (type == 'reminder' || link.startsWith('reminder:')) {
    final parts = link.split(':');
    final kind = parts.length > 1 ? parts[1] : '';
    final id = parts.length > 2 ? parts[2] : '';
    if (id.isEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => const CalendarPage()));
      return;
    }
    final api = ApiClient();
    try {
      if (kind == 'evt') {
        final res = await api.getJson('/api/events/$id');
        final ev = (res is Map ? (res['event'] ?? res) : null) as Map?;
        final ctx = navigatorKey.currentContext; // fresh, post-await
        if (ev == null || ctx == null) return;
        final card = {'card_type': 'event', ...ev.cast<String, dynamic>()};
        showAssetDetail(
          // ignore: use_build_context_synchronously — ctx re-fetched + null-checked above
          ctx,
          data: buildCard(
            payload: card,
            spec: synthesizeSpec('event'),
            displayName: 'event',
          ),
          payload: card,
          cardType: 'event',
          assetId: id,
        );
      } else {
        final res = await api.getJson('/api/assets/$id');
        final a = (res is Map ? (res['asset'] ?? res) : null) as Map?;
        if (a == null) return;
        final am = a.cast<String, dynamic>();
        final skill = am['user_skill_name'] as String? ?? 'todo';
        final payload =
            (am['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
        RenderSpec? spec;
        try {
          spec = (await fetchRenderSpecs(api))[skill];
        } catch (_) {}
        final ctx = navigatorKey.currentContext; // fresh, post-await
        if (ctx == null) return;
        showAssetDetail(
          // ignore: use_build_context_synchronously — ctx re-fetched + null-checked above
          ctx,
          data: buildCard(
            payload: payload,
            spec: spec ?? synthesizeSpec(skill),
            displayName: skill,
          ).copyWith(domain: am['domain'] as String?),
          payload: payload,
          cardType: skill,
          assetId: id,
          sessionId: am['session_id'] as String?,
          spec: spec,
        );
      }
    } catch (_) {
      nav.push(
        MaterialPageRoute(builder: (_) => const CalendarPage()),
      ); // fallback
    } finally {
      api.close();
    }
    return;
  }
  if (type == 'flash_done') {
    nav.push(
      MaterialPageRoute(
        builder: (_) => SessionDetailPage(sessionId: link, title: '闪念'),
      ),
    );
    return;
  }
  if (type == 'report_done') {
    try {
      final api = ApiClient();
      final res = await api.getJson('/api/reports/$link');
      api.close();
      final r = (res is Map ? res['report'] : null) as Map?;
      if (r != null) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => ReportViewerPage(
              title: r['title'] as String? ?? '报告',
              html: r['html'] as String? ?? '',
              reportId: link,
            ),
          ),
        );
      }
    } catch (_) {
      /* best-effort — a deleted report just doesn't open */
    }
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

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();

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
        position: Tween(
          begin: const Offset(0, -0.4),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
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
                      offset: const Offset(0, 8),
                    ),
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
                        border: Border.all(
                          color: eu.brand.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        widget.icon,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: eu.textHi,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.body.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                widget.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: eu.textMid,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
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
