import 'package:flutter/foundation.dart';

/// §9.2 通知收敛到 REKA — the single notification feed that lives on the pet.
/// Fed by: 快创 receipts, cosmetic drops, report-done, and server-pushed
/// notifications (AppEvents). The floating REKA shows the unread count as a
/// corner badge; the 通知 radial item opens a bubble panel over this list.
@immutable
class RekaNote {
  final String icon;   // emoji glyph
  final String title;
  final String? meta;
  final String type;   // 'report_done' | 'flash_done' | 'reminder' | 'task_done' … — for tap routing
  final String link;   // target ref (report_id / session_id / 'reminder:evt:<id>:<thr>' …)
  final bool read;
  final DateTime at;
  const RekaNote({
    required this.icon, required this.title, this.meta,
    this.type = '', this.link = '', this.read = false, required this.at,
  });

  bool get tappable => link.isNotEmpty;

  RekaNote markRead() =>
      RekaNote(icon: icon, title: title, meta: meta, type: type, link: link, read: true, at: at);
}

class RekaNotifications extends ChangeNotifier {
  RekaNotifications._();
  static final RekaNotifications instance = RekaNotifications._();

  final List<RekaNote> _items = [];
  List<RekaNote> get items => List.unmodifiable(_items);
  int get unread => _items.where((n) => !n.read).length;

  /// Push a new (unread) notification to the top. Lightly de-dupes an identical
  /// title fired back-to-back (e.g. a double refresh).
  void add({required String icon, required String title, String? meta, String type = '', String link = ''}) {
    if (_items.isNotEmpty && _items.first.title == title && _items.first.meta == meta && !_items.first.read) {
      return;
    }
    _items.insert(0, RekaNote(icon: icon, title: title, meta: meta, type: type, link: link, at: DateTime.now()));
    if (_items.length > 50) _items.removeRange(50, _items.length);
    notifyListeners();
  }

  /// Mark one note read (by identity) — tapped from the panel.
  void markReadNote(RekaNote n) {
    final i = _items.indexOf(n);
    if (i >= 0 && !_items[i].read) {
      _items[i] = _items[i].markRead();
      notifyListeners();
    }
  }

  void markAllRead() {
    if (unread == 0) return;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) _items[i] = _items[i].markRead();
    }
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
