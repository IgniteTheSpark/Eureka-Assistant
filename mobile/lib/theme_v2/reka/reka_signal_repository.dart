import '../../api/api_client.dart';
import 'reka_signal.dart';

class RekaSignalBatch {
  const RekaSignalBatch({
    required this.signals,
    required this.partialFailures,
    required this.generatedAt,
  });

  final List<RekaSignal> signals;
  final List<String> partialFailures;
  final DateTime? generatedAt;
}

abstract interface class RekaSignalRepository {
  Future<RekaSignalBatch> load({String timezoneName = 'Asia/Shanghai'});
  Future<void> dismiss(String signalId);
  Future<void> snooze(String signalId, DateTime remindAgainAt);
  Future<void> completeTodo(String assetId);
}

class ApiRekaSignalRepository implements RekaSignalRepository {
  ApiRekaSignalRepository([ApiClient? api])
    : _api = api ?? ApiClient(),
      _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<RekaSignalBatch> load({String timezoneName = 'Asia/Shanghai'}) async {
    final response = await _api.getJson(
      '/api/reka/signals',
      query: {'timezone': timezoneName},
    );
    final body = response is Map
        ? response.cast<String, dynamic>()
        : const <String, dynamic>{};
    final rows = body['signals'];
    final signals = <RekaSignal>[];
    if (rows is List) {
      for (final raw in rows.whereType<Map>()) {
        final signal = RekaSignal.tryParse(raw.cast<String, dynamic>());
        if (signal != null) signals.add(signal);
      }
    }
    final failures = body['partial_failures'];
    return RekaSignalBatch(
      signals: List<RekaSignal>.unmodifiable(signals),
      partialFailures: failures is List
          ? List<String>.unmodifiable(
              failures.whereType<String>().map((value) => value.trim()),
            )
          : const [],
      generatedAt: DateTime.tryParse(body['generated_at']?.toString() ?? ''),
    );
  }

  @override
  Future<void> dismiss(String signalId) async {
    await _api.postJson(
      '/api/reka/signals/${Uri.encodeComponent(signalId)}/dismiss',
      const <String, dynamic>{},
    );
  }

  @override
  Future<void> snooze(String signalId, DateTime remindAgainAt) async {
    await _api.postJson(
      '/api/reka/signals/${Uri.encodeComponent(signalId)}/snooze',
      <String, dynamic>{'remind_again_at': _utcZ(remindAgainAt)},
    );
  }

  @override
  Future<void> completeTodo(String assetId) async {
    await _api.putJson('/api/assets/${Uri.encodeComponent(assetId)}', {
      'payload_patch': {'status': 'done'},
    });
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
}

String _utcZ(DateTime value) =>
    value.toUtc().toIso8601String().replaceFirst(RegExp(r'\.000Z$'), 'Z');
