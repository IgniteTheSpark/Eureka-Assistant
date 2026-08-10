import '../../api/api_client.dart';
import '../../today/today_data.dart';
import '../reka/reka_signal.dart';
import '../reka/reka_signal_repository.dart';

abstract interface class ThemeV2HomeRepository {
  Future<TodayData> load();
}

class ApiThemeV2HomeRepository implements ThemeV2HomeRepository {
  ApiThemeV2HomeRepository({ApiClient? api, RekaSignalRepository? rekaSignals})
    : _api = api ?? ApiClient(),
      _ownsApi = api == null,
      _injectedRekaSignals = rekaSignals;

  final ApiClient _api;
  final bool _ownsApi;
  final RekaSignalRepository? _injectedRekaSignals;
  late final RekaSignalRepository rekaSignals =
      _injectedRekaSignals ?? ApiRekaSignalRepository(_api);

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
    final batch = await rekaSignals.load();
    return mapTodayRekaSignals(batch.signals);
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
}

/// Maps the dedicated persisted signal contract into Home's bounded queue.
/// Notification/report workflow receipts never pass through this path.
List<TodayRekaItem> mapTodayRekaSignals(Iterable<RekaSignal> signals) {
  final items = <TodayRekaItem>[];
  for (final signal in signals) {
    items.add(
      TodayRekaItem(
        id: signal.id,
        type: switch (signal.kind) {
          RekaSignalKind.overdue => 'overdue',
          RekaSignalKind.rhythmGap => 'rhythm_gap',
        },
        title: signal.title,
        body: signal.body,
        link: '',
        createdAt: signal.deliveredAt.toLocal(),
        naturalKey: signal.naturalKey,
        targetType: switch (signal.target.type) {
          RekaSignalTargetType.asset => 'asset',
          RekaSignalTargetType.skill => 'skill',
        },
        targetId: signal.target.id,
        actions: List<String>.unmodifiable(
          signal.actions.map(
            (action) => switch (action) {
              RekaSignalAction.open => 'open',
              RekaSignalAction.complete => 'complete',
              RekaSignalAction.reschedule => 'reschedule',
              RekaSignalAction.dismiss => 'dismiss',
            },
          ),
        ),
        expiresAt: signal.expiresAt?.toLocal(),
      ),
    );
  }
  items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return List<TodayRekaItem>.unmodifiable(items.take(20));
}
