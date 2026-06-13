import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

const recentSessionIdKey = 'eureka:recent_session_id';
const recentSessionTypeKey = 'eureka:recent_session_type';

class RecentSession {
  const RecentSession({required this.id, required this.type});

  final String id;
  final String type;

  bool get isValid => id.isNotEmpty && type.isNotEmpty;
}

class RecentSessionStore {
  const RecentSessionStore._();

  static Future<void> save({required String id, required String type}) async {
    final sid = id.trim();
    final kind = type.trim();
    if (sid.isEmpty || kind.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(recentSessionIdKey, sid);
      await sp.setString(recentSessionTypeKey, kind);
    } catch (_) {
      // Best-effort only: navigation can still fall back to ChatPage().
    }
  }

  static Future<void> clear() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(recentSessionIdKey);
      await sp.remove(recentSessionTypeKey);
    } catch (_) {
      // Best-effort only.
    }
  }

  static Future<RecentSession?> loadLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final id = sp.getString(recentSessionIdKey)?.trim() ?? '';
      final type = sp.getString(recentSessionTypeKey)?.trim() ?? '';
      if (id.isEmpty || type.isEmpty) return null;
      return RecentSession(id: id, type: type);
    } catch (_) {
      return null;
    }
  }

  static Future<RecentSession?> resolve({ApiClient? api}) async {
    final local = await loadLocal();
    if (local != null) return local;

    final ownsApi = api == null;
    final client = api ?? ApiClient();
    try {
      final res = await client.getJson('/api/sessions', query: {'limit': 1});
      final sessions = (res is Map ? res['sessions'] : null) as List?;
      Map? first;
      if (sessions != null) {
        for (final item in sessions) {
          if (item is Map) {
            first = item;
            break;
          }
        }
      }
      if (first == null) return null;
      final m = first.cast<String, dynamic>();
      final id = (m['id'] as String?)?.trim() ?? '';
      final type = (m['session_type'] as String?)?.trim() ?? '';
      if (id.isEmpty || type.isEmpty) return null;
      await save(id: id, type: type);
      return RecentSession(id: id, type: type);
    } catch (_) {
      return null;
    } finally {
      if (ownsApi) client.close();
    }
  }
}
