import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/asset_detail_sheet.dart';
import '../render/render_spec.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import 'session_detail_page.dart';

/// One notification from GET /api/notifications.
class NotifItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final String link;
  bool read;
  final DateTime createdAt;

  NotifItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.link,
    required this.read,
    required this.createdAt,
  });

  factory NotifItem.fromJson(Map<String, dynamic> j) => NotifItem(
        id: j['id'] as String? ?? '',
        type: j['type'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        link: j['link'] as String? ?? '',
        read: j['read'] == true,
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

/// Notifications surface (pushed from the bell). Tap a row to mark it read;
/// "全部已读" clears all.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _api = ApiClient();
  List<NotifItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getJson('/api/notifications');
      final list = (res is Map ? res['notifications'] : null) as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _items = list
            .whereType<Map>()
            .map((e) => NotifItem.fromJson(e.cast<String, dynamic>()))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markRead(NotifItem n) async {
    if (n.read) return;
    setState(() => n.read = true);
    try {
      await _api.postJson('/api/notifications/${n.id}/read', const {});
    } catch (_) {
      if (mounted) setState(() => n.read = false); // revert on failure
    }
  }

  // Tap a notification → mark read + navigate to its target (web notifNavigate):
  // flash_done → the capture session, reminder → the event, task_* → the asset.
  Future<void> _openNotif(NotifItem n) async {
    _markRead(n);
    final link = n.link;
    if (link.isEmpty) return;
    try {
      if (n.type == 'flash_done') {
        // 闪念 → its capture session (link is the bare session_id).
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SessionDetailPage(sessionId: link, title: '闪念')),
        );
      } else if (n.type == 'reminder') {
        // The scheduler stores a composite key, not a bare id:
        // "reminder:evt:<event_id>:<thr>" or "reminder:todo:<asset_id>:<thr>"
        // (UUIDs have no ':'). Parse out the kind + real id, then open the
        // right detail layer — event vs. todo(asset).
        final parts = link.split(':');
        final kind = parts.length > 1 ? parts[1] : '';
        final id = parts.length > 2 ? parts[2] : link;
        if (kind == 'evt') {
          final res = await _api.getJson('/api/events/$id');
          final ev = (res is Map ? (res['event'] ?? res) : null) as Map?;
          if (ev == null || !mounted) return;
          final card = {'card_type': 'event', ...ev.cast<String, dynamic>()};
          showAssetDetail(context,
              data: buildCard(payload: card, spec: synthesizeSpec('event'), displayName: 'event'),
              payload: card,
              cardType: 'event',
              assetId: id);
        } else {
          final res = await _api.getJson('/api/assets/$id');
          final a = (res is Map ? (res['asset'] ?? res) : null) as Map?;
          if (a == null || !mounted) return;
          final am = a.cast<String, dynamic>();
          final skill = am['user_skill_name'] as String? ?? 'todo';
          final payload = (am['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
          showAssetDetail(context,
              data: buildCard(payload: payload, spec: synthesizeSpec(skill), displayName: skill),
              payload: payload,
              cardType: skill,
              assetId: id);
        }
      } else if (n.type == 'task_done' || n.type == 'task_failed') {
        final res = await _api.getJson('/api/assets/$link');
        final a = ((res is Map ? res['asset'] : null) as Map?)?.cast<String, dynamic>();
        if (a == null || !mounted) return;
        final skill = a['user_skill_name'] as String? ?? 'misc';
        final payload = (a['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
        showAssetDetail(context,
            data: buildCard(payload: payload, spec: synthesizeSpec(skill), displayName: skill),
            payload: payload,
            cardType: skill,
            assetId: link);
      }
    } catch (_) {
      // navigation target gone / fetch failed — already marked read
    }
  }

  Future<void> _markAll() async {
    final prev = [for (final n in _items) n.read];
    setState(() {
      for (final n in _items) {
        n.read = true;
      }
    });
    try {
      await _api.postJson('/api/notifications/read-all', const {});
    } catch (_) {
      if (mounted) {
        setState(() {
          for (var i = 0; i < _items.length; i++) {
            _items[i].read = prev[i];
          }
        });
      }
    }
  }

  // Swipe-dismiss one notification (DELETE). Returns true on success so the
  // Dismissible animates out; false snaps it back.
  Future<bool> _dismiss(NotifItem n) async {
    try {
      await _api.deleteJson('/api/notifications/${n.id}');
      return true;
    } catch (_) {
      return false;
    }
  }

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
      appBar: AppBar(
        title: const Text('通知'),
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        actions: [
          if (_items.any((n) => !n.read))
            TextButton(onPressed: _markAll, child: const Text('全部已读')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('加载失败：$_error',
                        textAlign: TextAlign.center, style: TextStyle(color: eu.accentRed)),
                  ),
                )
              : _items.isEmpty
                  ? Center(child: Text('暂无通知', style: TextStyle(color: eu.textMid)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final n = _items[i];
                        return Dismissible(
                          key: ValueKey('notif_${n.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: eu.accentRed.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          confirmDismiss: (_) => _dismiss(n),
                          onDismissed: (_) => setState(() => _items.remove(n)),
                          child: _NotifRow(n, onTap: () => _openNotif(n)),
                        );
                      },
                    ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final NotifItem n;
  final VoidCallback onTap;
  const _NotifRow(this.n, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final (icon, accent) = _meta(eu, n.type);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.30)),
              ),
              child: Text(icon, style: TextStyle(color: accent, fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: TextStyle(
                          color: eu.textHi,
                          fontSize: 14,
                          fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                  if (n.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: eu.textMid, fontSize: 12)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_relativeTime(n.createdAt),
                        style: TextStyle(color: eu.textLo, fontSize: 11)),
                  ),
                ],
              ),
            ),
            if (!n.read)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: eu.brand, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  (String, Color) _meta(EurekaColors eu, String type) {
    switch (type) {
      case 'flash_done':
        return ('⚡', eu.accentBlue);
      case 'task_done':
        return ('✓', eu.accentGreen);
      case 'task_failed':
        return ('!', eu.accentRed);
      case 'reminder':
        return ('⏰', eu.accentPurple);
      default:
        return ('•', eu.textMid);
    }
  }
}

String _relativeTime(DateTime t) {
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 60) return '刚刚';
  if (s < 3600) return '${s ~/ 60} 分钟前';
  if (s < 86400) return '${s ~/ 3600} 小时前';
  if (s < 86400 * 7) return '${s ~/ 86400} 天前';
  return '${t.month}月${t.day}日';
}

/// Bell button (Calendar / Library headers) with an unread badge.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key});

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadUnread();
    // Near-live updates (the web uses an SSE stream; a 30s poll + a refresh on
    // any local mutation keeps the badge fresh without the stream plumbing).
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _loadUnread());
    dataRevision.addListener(_loadUnread);
  }

  @override
  void dispose() {
    _poll?.cancel();
    dataRevision.removeListener(_loadUnread);
    super.dispose();
  }

  Future<void> _loadUnread() async {
    final api = ApiClient();
    try {
      final res = await api.getJson('/api/notifications');
      final u = (res is Map ? res['unread'] : null);
      if (mounted && u is num) setState(() => _unread = u.toInt());
    } catch (_) {
      // ignore — badge just stays hidden
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: '通知',
          icon: Icon(Icons.notifications_none, color: eu.textMid),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
            _loadUnread(); // refresh badge after viewing
          },
        ),
        if (_unread > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: eu.accentRed, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}
