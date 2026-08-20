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

  test('debug API logs redact sensitive JSON body fields', () async {
    const requestBody = {
      'email': 'person@example.com',
      'purpose': 'register',
      'verification_code': '482913',
      'password': 'Secret123!',
    };
    const responseBody = {
      'ok': true,
      'token': 'qa-issued-jwt-token',
      'access_key_id': 'AKID-secret',
      'access_key_secret': 'SK-secret',
      'user': {'email': 'person@example.com'},
    };
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };

    try {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: true,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(responseBody),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );

      await api.postJson('/api/auth/verification-codes', requestBody);
      api.close();
    } finally {
      debugPrint = originalDebugPrint;
    }

    final output = messages.join('\n');
    expect(output, contains('"email":"[REDACTED]"'));
    expect(output, contains('"purpose":"register"'));
    expect(output, contains('"verification_code":"[REDACTED]"'));
    expect(output, contains('"password":"[REDACTED]"'));
    expect(output, contains('"token":"[REDACTED]"'));
    expect(output, contains('"access_key_id":"[REDACTED]"'));
    expect(output, contains('"access_key_secret":"[REDACTED]"'));
    expect(output, isNot(contains('482913')));
    expect(output, isNot(contains('Secret123!')));
    expect(output, isNot(contains('qa-issued-jwt-token')));
    expect(output, isNot(contains('AKID-secret')));
    expect(output, isNot(contains('SK-secret')));
    expect(output, isNot(contains('person@example.com')));
  });

  test('debug API logs leave non-sensitive JSON and non-JSON bodies intact',
      () async {
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };

    try {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: true,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'resend_delay_seconds': 60}),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );

      await api.postJson('/api/auth/verification-codes', {
        'purpose': 'register',
        'resend_delay_seconds': 60,
      });
      api.close();
    } finally {
      debugPrint = originalDebugPrint;
    }

    final output = messages.join('\n');
    expect(output, contains('"purpose":"register"'));
    expect(output, contains('"resend_delay_seconds":60'));
    expect(output, contains('[API]'));
  });
}
