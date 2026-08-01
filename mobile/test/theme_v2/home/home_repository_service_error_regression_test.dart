import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'surfaces an initial error when the Theme V2 service is unavailable',
    () {
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient(
          (_) async => http.Response('{"detail":"unavailable"}', 503),
        ),
      );
      addTearDown(api.close);
      final repository = ApiThemeV2HomeRepository(api: api);

      expect(
        repository.load(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
    },
  );
}
