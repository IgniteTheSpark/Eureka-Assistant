import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// One notification from GET /api/notifications.
class NotifItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final String link;
  final bool read;
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

Future<List<NotifItem>> fetchNotifications(ApiClient api) async {
  final res = await api.getJson('/api/notifications');
  final list = (res is Map ? res['notifications'] : null) as List? ?? const [];
  return list
      .whereType<Map>()
      .map((e) => NotifItem.fromJson(e.cast<String, dynamic>()))
      .toList();
}

/// Notifications surface (pushed from the bell).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _api = ApiClient();
  late final Future<List<NotifItem>> _future = fetchNotifications(_api);

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
      ),
      body: FutureBuilder<List<NotifItem>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('加载失败：${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: eu.accentRed)),
              ),
            );
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return Center(child: Text('暂无通知', style: TextStyle(color: eu.textMid)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            itemBuilder: (_, i) => _NotifRow(items[i]),
          );
        },
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final NotifItem n;
  const _NotifRow(this.n);

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final (icon, accent) = _meta(eu, n.type);
    return Container(
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

/// Bell button used in the Calendar / Library headers.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '通知',
      icon: Icon(Icons.notifications_none, color: context.eu.textMid),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      ),
    );
  }
}
