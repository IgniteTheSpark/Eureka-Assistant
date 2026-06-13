import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/chat/recent_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves, loads and clears the recent session locally', () async {
    await RecentSessionStore.save(id: 'flash-1', type: 'flash');

    final saved = await RecentSessionStore.loadLocal();
    expect(saved?.id, 'flash-1');
    expect(saved?.type, 'flash');

    await RecentSessionStore.clear();
    expect(await RecentSessionStore.loadLocal(), isNull);
  });

  test(
    'falls back to GET /api/sessions?limit=1 when local state is empty',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost',
        enableLogging: false,
        client: MockClient((request) async {
          expect(request.url.path, '/api/sessions');
          expect(request.url.queryParameters['limit'], '1');
          return http.Response(
            jsonEncode({
              'sessions': [
                {'id': 'chat-1', 'session_type': 'chat'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final resolved = await RecentSessionStore.resolve(api: api);

      expect(resolved?.id, 'chat-1');
      expect(resolved?.type, 'chat');
      final persisted = await RecentSessionStore.loadLocal();
      expect(persisted?.id, 'chat-1');
      expect(persisted?.type, 'chat');
    },
  );
}
