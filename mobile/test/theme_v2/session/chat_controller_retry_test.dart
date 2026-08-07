import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/api/sse_client.dart';
import 'package:eureka/chat/chat_controller.dart';
import 'package:eureka/chat/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('agent work phase advances monotonically across SSE frames', () async {
    final events = StreamController<SseEvent>();
    final controller = ChatController(turnStream: (_, _) => events.stream);
    addTearDown(() async {
      await events.close();
      controller.dispose();
    });

    final pending = controller.send('帮我查一下并回答');
    await Future<void>.delayed(Duration.zero);
    final agent = controller.messages.last;
    expect(agent.workPhase, AgentWorkPhase.understanding);

    events.add(SseEvent('tool_call', {'name': 'tool_query_asset'}));
    await Future<void>.delayed(Duration.zero);
    expect(agent.workPhase, AgentWorkPhase.executing);

    events.add(SseEvent('token', {'text': '查到了'}));
    await Future<void>.delayed(Duration.zero);
    expect(agent.workPhase, AgentWorkPhase.composing);

    events.add(SseEvent('tool_result', {'name': 'late-tool'}));
    await Future<void>.delayed(Duration.zero);
    expect(agent.workPhase, AgentWorkPhase.composing);

    await events.close();
    await pending;
  });

  test(
    'retry replays the failed turn without duplicating the user message',
    () async {
      var attempts = 0;
      final controller = ChatController(
        turnStream: (_, _) {
          attempts++;
          if (attempts == 1) {
            return Stream<SseEvent>.error(StateError('offline'));
          }
          return Stream<SseEvent>.fromIterable([
            SseEvent('token', {'text': '已恢复'}),
            SseEvent('done', {'elapsed_ms': 12}),
          ]);
        },
      );
      addTearDown(controller.dispose);

      await controller.send('整理这段录音');
      expect(controller.error, isNotNull);
      expect(
        controller.messages.where((message) => message.isUser),
        hasLength(1),
      );

      await controller.retryLastFailedTurn();

      expect(attempts, 2);
      expect(controller.error, isNull);
      expect(
        controller.messages.where((message) => message.isUser),
        hasLength(1),
      );
      expect(
        controller.messages
            .where((message) => !message.isUser)
            .expand((message) => message.parts)
            .whereType<TextPart>()
            .map((part) => part.text),
        contains('已恢复'),
      );
    },
  );

  test('an SSE error frame becomes a retryable controller error', () async {
    var attempts = 0;
    final controller = ChatController(
      turnStream: (_, _) {
        attempts++;
        if (attempts == 1) {
          return Stream<SseEvent>.value(
            SseEvent('error', {'message': '录音不可访问'}),
          );
        }
        return Stream<SseEvent>.value(SseEvent('token', {'text': '重试成功'}));
      },
    );
    addTearDown(controller.dispose);

    await controller.send('整理录音');
    expect(controller.error, '录音不可访问');

    await controller.retryLastFailedTurn();
    expect(attempts, 2);
    expect(
      controller.messages.where((message) => message.isUser),
      hasLength(1),
    );
  });

  test(
    'live meta assigns the exact input turn to the local turn pair',
    () async {
      final controller = ChatController(
        turnStream: (_, _) => Stream<SseEvent>.fromIterable([
          SseEvent('meta', {
            'session_id': 'session-1',
            'input_turn_id': 'turn-2',
          }),
          SseEvent('done', const {}),
        ]),
      );
      addTearDown(controller.dispose);

      await controller.send('定位这一轮');

      expect(controller.messages, hasLength(2));
      expect(
        controller.messages.map((message) => message.inputTurnId),
        everyElement('turn-2'),
      );
    },
  );

  test(
    'reset prevents late SSE frames from contaminating a new session',
    () async {
      final events = StreamController<SseEvent>();
      final controller = ChatController(turnStream: (_, _) => events.stream);
      addTearDown(() async {
        await events.close();
        controller.dispose();
      });

      final pendingSend = controller.send('旧会话消息');
      await Future<void>.delayed(Duration.zero);
      controller.reset();
      events
        ..add(SseEvent('meta', {'session_id': 'stale-session'}))
        ..add(SseEvent('error', {'message': 'stale-error'}));
      await events.close();
      await pendingSend;

      expect(controller.sessionId, isNull);
      expect(controller.error, isNull);
      expect(controller.messages, isEmpty);
      expect(controller.streaming, isFalse);
    },
  );

  test('reset ignores a late lazy-session creation', () async {
    final createResponse = Completer<http.Response>();
    final api = ApiClient(
      client: MockClient((request) {
        expect(request.method, 'POST');
        return createResponse.future;
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(
      api: api,
      turnStream: (_, _) => const Stream<SseEvent>.empty(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    controller
      ..subjectType = 'asset'
      ..subjectId = 'asset-old';
    final pendingSend = controller.send('旧主题消息');
    await Future<void>.delayed(Duration.zero);
    controller.reset();
    createResponse.complete(
      http.Response(jsonEncode({'session_id': 'stale-created'}), 200),
    );
    await pendingSend;

    expect(controller.sessionId, isNull);
    expect(controller.messages, isEmpty);
    expect(controller.streaming, isFalse);
  });

  test('the latest concurrent history load wins atomically', () async {
    final responses = <String, Completer<http.Response>>{
      for (final id in ['a', 'b'])
        '/api/sessions/$id/messages': Completer<http.Response>(),
      for (final id in ['a', 'b'])
        '/api/sessions/$id': Completer<http.Response>(),
    };
    final api = ApiClient(
      client: MockClient((request) => responses[request.url.path]!.future),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(api: api);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    final loadA = controller.loadSession('a', title: '会话 A');
    final loadB = controller.loadSession('b', title: '会话 B');
    responses['/api/sessions/b/messages']!.complete(
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'messages': [
              {'id': 'ub', 'role': 'user', 'text': 'B 内容'},
            ],
          }),
        ),
        200,
      ),
    );
    responses['/api/sessions/b']!.complete(
      http.Response(jsonEncode({'session': {}}), 200),
    );
    await loadB;
    responses['/api/sessions/a/messages']!.complete(
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'messages': [
              {'id': 'ua', 'role': 'user', 'text': 'A 内容'},
            ],
          }),
        ),
        200,
      ),
    );
    responses['/api/sessions/a']!.complete(
      http.Response(jsonEncode({'session': {}}), 200),
    );
    await loadA;

    expect(controller.sessionId, 'b');
    expect(controller.displayTitle, '会话 B');
    expect(controller.messages.single.text, 'B 内容');
  });

  test('history replay preserves input turn provenance', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/messages')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'messages': [
                  {
                    'id': 'u2',
                    'role': 'user',
                    'text': '第二轮输入',
                    'input_turn_id': 'turn-2',
                  },
                ],
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode({'session': {}}), 200);
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(api: api);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.loadSession('session-1');

    expect(controller.messages.single.inputTurnId, 'turn-2');
  });

  test('history replay restores every persisted tool round', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/messages')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'messages': [
                  {
                    'id': 'a1',
                    'role': 'agent',
                    'status': 'done',
                    'text': '已经找到并更新了刚才的记录。',
                    'tool_call': {
                      'calls': [
                        {'name': 'tool_query_assets'},
                        {'name': 'tool_update_asset'},
                      ],
                    },
                    'tool_result': {
                      'results': [
                        {
                          'name': 'tool_query_assets',
                          'response': {'count': 1},
                        },
                        {
                          'name': 'tool_update_asset',
                          'response': {'ok': true},
                        },
                      ],
                    },
                    'elapsed_ms': 88,
                    'total_tokens': 31,
                    'cards': const [],
                  },
                ],
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode({'session': {}}), 200);
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(api: api);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.loadSession('session-1');

    final agent = controller.messages.single;
    expect(agent.parts.whereType<ToolCallPart>().map((part) => part.name), [
      'tool_query_assets',
      'tool_update_asset',
    ]);
    expect(agent.parts.whereType<ToolResultPart>().map((part) => part.name), [
      'tool_query_assets',
      'tool_update_asset',
    ]);
    expect(agent.elapsedMs, 88);
    expect(agent.tokens, 31);
  });

  test('a session cannot be restored after deletion has started', () async {
    final deleteResponse = Completer<http.Response>();
    final messagesResponse = Completer<http.Response>();
    final detailResponse = Completer<http.Response>();
    final api = ApiClient(
      client: MockClient((request) {
        if (request.method == 'DELETE') return deleteResponse.future;
        if (request.url.path.endsWith('/messages')) {
          return messagesResponse.future;
        }
        return detailResponse.future;
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(api: api);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    final deleting = controller.deleteSession('deleted');
    await Future<void>.delayed(Duration.zero);
    final loading = controller.loadSession('deleted');
    deleteResponse.complete(http.Response('', 204));
    messagesResponse.complete(
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'messages': [
              {'id': 'stale', 'role': 'user', 'text': '不应恢复'},
            ],
          }),
        ),
        200,
      ),
    );
    detailResponse.complete(http.Response(jsonEncode({'session': {}}), 200));
    await deleting;
    await loading;

    expect(controller.sessionId, isNull);
    expect(controller.messages, isEmpty);
  });

  test('a new send invalidates an unfinished session restore', () async {
    final historyResponse = Completer<http.Response>();
    final api = ApiClient(
      client: MockClient((request) {
        if (request.url.path.endsWith('/messages')) {
          return historyResponse.future;
        }
        return Future.value(http.Response(jsonEncode({'session': {}}), 200));
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final turnEvents = StreamController<SseEvent>();
    final controller = ChatController(
      api: api,
      turnStream: (_, _) => turnEvents.stream,
    );
    addTearDown(() async {
      await turnEvents.close();
      controller.dispose();
      api.close();
    });

    final restoring = controller.loadSession('restored');
    final sending = controller.send('刚输入的新消息');
    await Future<void>.delayed(Duration.zero);
    historyResponse.complete(
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'messages': [
              {'id': 'old', 'role': 'user', 'text': '旧会话内容'},
            ],
          }),
        ),
        200,
      ),
    );
    await restoring;
    turnEvents
      ..add(SseEvent('token', {'text': '新回复'}))
      ..add(SseEvent('done', const {}));
    await turnEvents.close();
    await sending;

    expect(
      controller.messages.where((message) => message.isUser).single.text,
      '刚输入的新消息',
    );
    expect(controller.messages.last.text, '新回复');
  });

  test('a failed history load preserves the current retry target', () async {
    var attempts = 0;
    final api = ApiClient(
      client: MockClient((_) async => http.Response('unavailable', 503)),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(
      api: api,
      turnStream: (_, _) {
        attempts++;
        if (attempts == 1) {
          return Stream<SseEvent>.error(StateError('offline'));
        }
        return Stream<SseEvent>.value(SseEvent('token', {'text': '重试成功'}));
      },
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.send('保留这次重试');
    await expectLater(controller.loadSession('broken'), throwsA(isA<Object>()));
    await controller.retryLastFailedTurn();

    expect(attempts, 2);
    expect(controller.error, isNull);
  });

  test('durable running history blocks a second local turn', () async {
    var turnAttempts = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/messages')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'messages': [
                  {'id': 'u1', 'role': 'user', 'text': '正在执行'},
                  {'id': 'a1', 'role': 'agent', 'status': 'running'},
                ],
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode({'session': {}}), 200);
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(
      api: api,
      turnStream: (_, _) {
        turnAttempts++;
        return const Stream<SseEvent>.empty();
      },
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.loadSession('running-session');
    expect(controller.streaming, isTrue);
    await controller.send('不应并发发送');

    expect(turnAttempts, 0);
  });

  test('failed durable reconciliation unlocks with a reload retry', () async {
    var messageLoads = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/messages')) {
          messageLoads++;
          if (messageLoads == 2) return http.Response('offline', 503);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'messages': [
                  {'id': 'u1', 'role': 'user', 'text': '执行任务'},
                  {
                    'id': 'a1',
                    'role': 'agent',
                    'status': messageLoads == 1 ? 'running' : 'done',
                    'text': messageLoads == 1 ? '' : '执行完成',
                  },
                ],
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode({'session': {}}), 200);
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(
      api: api,
      reconcileInterval: const Duration(milliseconds: 1),
      reconcileTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.loadSession('durable');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(controller.streaming, isFalse);
    expect(controller.error, isNotNull);

    await controller.retryLastFailedTurn();

    expect(messageLoads, 3);
    expect(controller.error, isNull);
    expect(controller.messages.last.text, '执行完成');
  });

  test('durable reconciliation timeout also bounds a hung request', () async {
    var messageLoads = 0;
    final hungResponse = Completer<http.Response>();
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/messages')) {
          messageLoads++;
          if (messageLoads > 1) return hungResponse.future;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'messages': [
                  {'id': 'a1', 'role': 'agent', 'status': 'running'},
                ],
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode({'session': {}}), 200);
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(
      api: api,
      reconcileInterval: const Duration(milliseconds: 1),
      reconcileTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.loadSession('hung-durable');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.streaming, isFalse);
    expect(controller.error, isNotNull);
  });

  test(
    'an obsolete durable poll cannot poison a reloaded same-id session',
    () async {
      var aMessageLoads = 0;
      final obsoletePoll = Completer<http.Response>();
      final api = ApiClient(
        client: MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/sessions/a/messages') {
            aMessageLoads++;
            if (aMessageLoads == 1) {
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'messages': [
                      {'id': 'a-running', 'role': 'agent', 'status': 'running'},
                    ],
                  }),
                ),
                200,
              );
            }
            if (aMessageLoads == 2) return obsoletePoll.future;
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'messages': [
                    {
                      'id': 'a-done',
                      'role': 'agent',
                      'status': 'done',
                      'text': 'A 已完成',
                    },
                  ],
                }),
              ),
              200,
            );
          }
          if (path == '/api/sessions/b/messages') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({'messages': const []})),
              200,
            );
          }
          return http.Response(jsonEncode({'session': {}}), 200);
        }),
        baseUrl: 'http://test',
        enableLogging: false,
      );
      final controller = ChatController(
        api: api,
        reconcileInterval: const Duration(milliseconds: 1),
        reconcileTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(() {
        controller.dispose();
        api.close();
      });

      await controller.loadSession('a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(aMessageLoads, 2);
      await controller.loadSession('b');
      await controller.loadSession('a');
      obsoletePoll.complete(http.Response('offline', 503));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(controller.sessionId, 'a');
      expect(controller.messages.single.text, 'A 已完成');
      expect(controller.streaming, isFalse);
      expect(controller.error, isNull);
    },
  );

  test('attached context labels become controller-owned state', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(jsonEncode({'session_id': 'created'}), 200);
        }
        return http.Response('{}', 200);
      }),
      baseUrl: 'http://test',
      enableLogging: false,
    );
    final controller = ChatController(api: api);
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    final attached = await controller.attachContexts(
      ['asset-b'],
      labels: const {'asset-b': '资产 B'},
    );
    await controller.attachContexts(
      ['asset-b'],
      labels: const {'asset-b': '资产 B'},
    );

    expect(attached, isTrue);
    expect(controller.contextAssets, [(id: 'asset-b', label: '资产 B')]);
  });
}
