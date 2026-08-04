import '../../api/api_client.dart';
import '../../today/today_data.dart';

abstract interface class ThemeV2HomeRepository {
  Future<TodayData> load();
}

class ApiThemeV2HomeRepository implements ThemeV2HomeRepository {
  ApiThemeV2HomeRepository({ApiClient? api})
    : _api = api ?? ApiClient(),
      _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<TodayData> load() async {
    await _api.getJson('/ready');
    final todayFuture = loadToday(_api, coreRecordsOnly: true);
    final rekaFuture = _loadRekaQueue().catchError(
      (_) => const <TodayRekaItem>[],
    );
    final today = await todayFuture;
    final rekaQueue = await rekaFuture;
    return today.withRekaQueue(rekaQueue);
  }

  Future<List<TodayRekaItem>> _loadRekaQueue() async {
    final response = await _api.getJson('/api/notifications');
    final rows = response is Map ? response['notifications'] : null;
    return mapTodayRekaNotifications(rows is List ? rows : const []);
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
}

const _todayRekaNotificationTypes = <String>{
  'reminder',
  'report_available',
  'report_plan_ready',
  'report_done',
  'report_failed',
};

/// Maps only explicit assistant signals into Home's Reka queue.
///
/// Todo/task rows and capture completion receipts are deliberately excluded:
/// they belong to Agenda/notifications, not to Reka discoveries.
List<TodayRekaItem> mapTodayRekaNotifications(Iterable<dynamic> rows) {
  final items = <TodayRekaItem>[];
  for (final raw in rows.whereType<Map>()) {
    final row = raw.cast<String, dynamic>();
    final type = row['type']?.toString().trim() ?? '';
    if (!_todayRekaNotificationTypes.contains(type) || row['read'] == true) {
      continue;
    }
    final id = row['id']?.toString().trim() ?? '';
    final title = row['title']?.toString().trim() ?? '';
    if (id.isEmpty || title.isEmpty) continue;
    items.add(
      TodayRekaItem(
        id: id,
        type: type,
        title: title,
        body: row['body']?.toString().trim() ?? '',
        link: row['link']?.toString().trim() ?? '',
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }
  items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return List<TodayRekaItem>.unmodifiable(items.take(20));
}
