import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'maps only unread explicit Reka notifications in newest-first order',
    () {
      final items = mapTodayRekaNotifications([
        {
          'id': 'todo-status',
          'type': 'task_done',
          'title': '普通任务已完成',
          'read': false,
          'created_at': '2026-08-04T03:00:00Z',
        },
        {
          'id': 'capture-receipt',
          'type': 'flash_done',
          'title': '闪念已整理',
          'read': false,
          'created_at': '2026-08-04T04:00:00Z',
        },
        {
          'id': 'old-read',
          'type': 'report_available',
          'title': '已读发现',
          'read': true,
          'created_at': '2026-08-04T05:00:00Z',
        },
        {
          'id': 'reminder',
          'type': 'reminder',
          'title': '会前提醒',
          'body': '会议将在一小时后开始',
          'link': 'reminder:evt:event-1:t60',
          'read': false,
          'created_at': '2026-08-04T02:00:00Z',
        },
        {
          'id': 'summary',
          'type': 'report_available',
          'title': '可以整理本周记录',
          'body': '已积累足够素材',
          'link': 'report-start:execution-1:1',
          'read': false,
          'created_at': '2026-08-04T06:00:00Z',
        },
      ]);

      expect(items.map((item) => item.id), ['summary', 'reminder']);
    },
  );

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
