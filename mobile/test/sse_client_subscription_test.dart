import 'package:eureka/api/api_client.dart';
import 'package:eureka/api/sse_client.dart';
import 'package:eureka/data_revision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'successful SSE subscription and reconnect each request one catch-up',
    () async {
      final catchUpBefore = dataLibraryCatchUpRevision.value;
      addTearDown(() => dataLibraryCatchUpRevision.value = catchUpBefore);
      final client = MockClient(
        (_) async => http.Response(
          'event: capture\ndata: {"id":"one"}\n\n'
          'event: notification\ndata: {"id":"two"}\n\n',
          200,
          headers: const {'content-type': 'text/event-stream'},
        ),
      );

      final first = await getSse(
        '/api/notifications/stream',
        baseUrl: 'http://theme-v2.test',
        client: client,
        onSubscribed: requestLibraryCatchUp,
      ).toList();
      await Future<void>.delayed(Duration.zero);
      expect(first, hasLength(2));
      expect(dataLibraryCatchUpRevision.value, catchUpBefore + 1);

      final second = await getSse(
        '/api/notifications/stream',
        baseUrl: 'http://theme-v2.test',
        client: client,
        onSubscribed: requestLibraryCatchUp,
      ).toList();
      await Future<void>.delayed(Duration.zero);
      expect(second, hasLength(2));
      expect(dataLibraryCatchUpRevision.value, catchUpBefore + 2);
    },
  );

  test('failed SSE subscription does not request Library catch-up', () async {
    final catchUpBefore = dataLibraryCatchUpRevision.value;
    addTearDown(() => dataLibraryCatchUpRevision.value = catchUpBefore);
    final client = MockClient((_) async => http.Response('unauthorized', 401));

    await expectLater(
      getSse(
        '/api/notifications/stream',
        baseUrl: 'http://theme-v2.test',
        client: client,
        onSubscribed: requestLibraryCatchUp,
      ).toList(),
      throwsA(isA<ApiException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(dataLibraryCatchUpRevision.value, catchUpBefore);
  });
}
