import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/api/auth_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('debug API logs redact the Authorization header', () async {
    const secret = 'qa-secret-bearer-token';
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    AuthStore.token = secret;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };

    try {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: true,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );

      await api.getJson('/health');
      api.close();
    } finally {
      AuthStore.token = null;
      debugPrint = originalDebugPrint;
    }

    final output = messages.join('\n');
    expect(output, contains('Authorization: [REDACTED]'));
    expect(output, isNot(contains(secret)));
  });
}
