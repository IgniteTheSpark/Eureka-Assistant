import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

/// §9.2 通知收敛到 REKA — the single notification feed that lives on the pet.
/// Fed by: 快创 receipts, cosmetic drops, report-done, server-pushed
/// notifications (AppEvents SSE), and — on app open — the **server's 14-day
/// history** ([loadFromServer], handoff-reka-emote-notif.md §C). The floating
/// REKA shows the unread count as a corner badge; the 通知 radial item opens a
/// bubble panel over this list.
@immutable
class RekaNote {
  final String id; // server notification id ('' = client-only receipt)
  final String icon; // emoji glyph (slice A → Kenney emote sprite)
  final String title;
  final String? meta;
  final String
  type; // 'report_done' | 'flash_done' | 'reminder' | 'task_done' | 'nudge' … — tap routing
  final String
  link; // target ref (report_id / session_id / 'reminder:evt:<id>:<thr>' …)
  final bool read;
  final DateTime at;
  const RekaNote({
    this.id = '',
    required this.icon,
    required this.title,
    this.meta,
    this.type = '',
    this.link = '',
    this.read = false,
    required this.at,
  });

  bool get tappable => link.isNotEmpty;

  RekaNote markRead() => RekaNote(
    id: id,
    icon: icon,
    title: title,
    meta: meta,
    type: type,
    link: link,
    read: true,
    at: at,
  );
}

class RekaNotifications extends ChangeNotifier {
  RekaNotifications._();
  static final RekaNotifications instance = RekaNotifications._();

  final List<RekaNote> _items = [];
  List<RekaNote> get items => List.unmodifiable(_items);
  int get unread => _items.where((n) => !n.read).length;

  final _api = ApiClient();

  /// §C 持久化:开 app 从 `GET /api/notifications` 拉服务端 **14 天历史**(含已读 /
  /// 已 dismiss),让 feed 重进不空。服务端是持久化通知的真值,故用它替换内存列表;
  /// SSE 随后把实时来的加在最前。离线 / 未登录 → 静默保留内存里已有的。
  Future<void> loadFromServer() async {
    try {
      final res = await _api.getJson(
        '/api/notifications',
        query: {'limit': 100},
      );
      final list =
          (res is Map ? res['notifications'] : null) as List? ?? const [];
      final loaded = list
          .whereType<Map>()
          .map((m) => _fromJson(m.cast<String, dynamic>()))
          .toList();
      _items
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    } catch (_) {
      // offline / not authed — keep whatever's already in memory.
    }
  }

  RekaNote _fromJson(Map<String, dynamic> m) => RekaNote(
    id: m['id'] as String? ?? '',
    icon: iconFor(m['type'] as String? ?? ''),
    title: m['title'] as String? ?? '',
    meta: (m['body'] as String?)?.trim().isNotEmpty == true
        ? (m['body'] as String).trim()
        : null,
    type: m['type'] as String? ?? '',
    link: m['link'] as String? ?? '',
    read: m['read'] == true,
    at:
        DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  /// Gentle-only icon per notification type (handoff §A; slice A swaps these for
  /// the Kenney emote sprites). **Never a negative face** (§14.8).
  static String iconFor(String type) {
    switch (type) {
      case 'nudge':
        return '💡';
      case 'flash_done':
        return '🎤';
      case 'task_done':
        return '✨';
      case 'task_failed':
        return '💧'; // gentle drop, not a sad face
      case 'reminder':
        return '❗';
      default:
        return '🔔';
    }
  }

  /// Push a new (unread) notification to the top. Lightly de-dupes an identical
  /// title fired back-to-back (e.g. a double refresh).
  void add({
    required String icon,
    required String title,
    String? meta,
    String type = '',
    String link = '',
    String id = '',
  }) {
    if (_items.isNotEmpty &&
        _items.first.title == title &&
        _items.first.meta == meta &&
        !_items.first.read) {
      return;
    }
    _items.insert(
      0,
      RekaNote(
        id: id,
        icon: icon,
        title: title,
        meta: meta,
        type: type,
        link: link,
        at: DateTime.now(),
      ),
    );
    if (_items.length > 100) _items.removeRange(100, _items.length);
    notifyListeners();
  }

  /// Mark one note read (by identity) — tapped / dismissed from the panel.
  /// §C: dismiss ≠ delete — flip `read` on the server too; the row stays in feed.
  void markReadNote(RekaNote n) {
    final i = _items.indexOf(n);
    if (i >= 0 && !_items[i].read) {
      final id = _items[i].id;
      _items[i] = _items[i].markRead();
      notifyListeners();
      if (id.isNotEmpty) {
        unawaited(
          _api
              .postJson(
                '/api/notifications/$id/read',
                const <String, dynamic>{},
              )
              .catchError((_) => null),
        );
      }
    }
  }

  void markAllRead() {
    if (unread == 0) return;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) _items[i] = _items[i].markRead();
    }
    notifyListeners();
    unawaited(
      _api
          .postJson('/api/notifications/read-all', const <String, dynamic>{})
          .catchError((_) => null),
    );
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
