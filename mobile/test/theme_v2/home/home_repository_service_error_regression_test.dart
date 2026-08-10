import 'package:eureka/api/api_client.dart';
import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/theme_v2/reka/reka_signal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'maps only persisted Reka signals and never report workflow receipts',
    () {
      final items = mapTodayRekaSignals([
        RekaSignal(
          id: 'overdue',
          naturalKey: 'overdue:todo-1:deadline',
          kind: RekaSignalKind.overdue,
          title: '提交费用单 已到截止时间',
          body: '仍未完成',
          target: const RekaSignalTarget(
            type: RekaSignalTargetType.asset,
            id: 'todo-1',
          ),
          actions: const [
            RekaSignalAction.open,
            RekaSignalAction.complete,
            RekaSignalAction.reschedule,
            RekaSignalAction.dismiss,
          ],
          deliveredAt: DateTime.parse('2026-08-04T06:00:00Z'),
        ),
        RekaSignal(
          id: 'rhythm',
          naturalKey: 'rhythm:expense:daily:any:cycle',
          kind: RekaSignalKind.rhythmGap,
          title: '消费还没有记录',
          body: '可以现在补上一笔',
          target: const RekaSignalTarget(
            type: RekaSignalTargetType.skill,
            id: 'expense',
          ),
          actions: const [RekaSignalAction.open, RekaSignalAction.dismiss],
          deliveredAt: DateTime.parse('2026-08-04T07:00:00Z'),
        ),
      ]);

      expect(items.map((item) => item.id), ['rhythm', 'overdue']);
      expect(items.first.type, 'rhythm_gap');
      expect(items.first.targetType, 'skill');
      expect(items.first.targetId, 'expense');
      expect(items.last.actions, ['open', 'complete', 'reschedule', 'dismiss']);
      expect(items.every((item) => item.link.isEmpty), isTrue);
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
