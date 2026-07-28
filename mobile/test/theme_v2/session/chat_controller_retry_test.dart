import 'package:eureka/api/sse_client.dart';
import 'package:eureka/chat/chat_controller.dart';
import 'package:eureka/chat/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
