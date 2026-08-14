import 'dart:async';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/reka/reka_signal_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home data starts while the readiness probe is still pending', () async {
    final api = _RecordingApiClient();
    final repository = ApiThemeV2HomeRepository(
      api: api,
      rekaSignals: const _EmptyRekaSignalRepository(),
    );

    final loading = repository.load();
    await Future<void>.delayed(Duration.zero);

    expect(api.paths, contains('/ready'));
    expect(api.paths, contains('/api/assets'));

    api.ready.complete(<String, dynamic>{});
    await loading;
  });
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(baseUrl: 'http://test', enableLogging: false);

  final List<String> paths = [];
  final Completer<dynamic> ready = Completer<dynamic>();

  @override
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    paths.add(path);
    if (path == '/ready') return ready.future;
    if (path == '/api/user-skills') return {'skills': <dynamic>[]};
    if (path == '/api/assets') return {'assets': <dynamic>[]};
    if (path == '/api/events') return {'events': <dynamic>[]};
    if (path == '/api/contacts') return {'contacts': <dynamic>[]};
    if (path.startsWith('/api/flash/sessions/')) return {'session': null};
    return <String, dynamic>{};
  }
}

class _EmptyRekaSignalRepository implements RekaSignalRepository {
  const _EmptyRekaSignalRepository();

  @override
  Future<void> completeTodo(String assetId) async {}

  @override
  Future<void> dismiss(String signalId) async {}

  @override
  Future<RekaSignalBatch> load({String timezoneName = 'Asia/Shanghai'}) async {
    return const RekaSignalBatch(
      signals: [],
      partialFailures: [],
      generatedAt: null,
    );
  }

  @override
  Future<void> snooze(String signalId, DateTime remindAgainAt) async {}
}
