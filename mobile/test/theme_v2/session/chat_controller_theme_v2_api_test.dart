import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/chat/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'precipitation resolves the Theme V2 skill id before creating',
    () async {
      Map<String, dynamic>? created;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/user-skills') {
            return http.Response(
              jsonEncode([
                {'id': 'skill-notes', 'machine_name': 'notes'},
              ]),
              200,
            );
          }
          if (request.method == 'POST' && request.url.path == '/api/assets') {
            created = (jsonDecode(request.body) as Map).cast<String, dynamic>();
            return http.Response(jsonEncode({'id': 'asset-1'}), 200);
          }
          return http.Response('not found', 404);
        }),
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
      );
      final controller = ChatController(api: api)..sessionId = 'session-1';
      addTearDown(() {
        controller.dispose();
        api.close();
      });

      await controller.precipitate('今天跑了五公里', 'notes');

      expect(created, {
        'user_skill_id': 'skill-notes',
        'payload': {'title': '今天跑了五公里', 'content': '今天跑了五公里'},
        'session_id': 'session-1',
      });
      expect(created, isNot(contains('user_skill_name')));
    },
  );

  test('todo precipitation uses the required title field', () async {
    Map<String, dynamic>? created;
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {'id': 'skill-todo', 'machine_name': 'todo'},
            ]),
            200,
          );
        }
        created = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(jsonEncode({'id': 'asset-1'}), 200);
      }),
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
    );
    final controller = ChatController(api: api);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.precipitate('提交本周报告', 'todo');

    expect(created?['payload'], {'title': '提交本周报告'});
  });
}
