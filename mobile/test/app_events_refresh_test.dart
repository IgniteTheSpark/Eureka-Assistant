import 'dart:convert';

import 'package:eureka/app_events.dart';
import 'package:eureka/data_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    dataRevision.value = 0;
    dataMutationRevision.value = 0;
    dataLibraryCatchUpRevision.value = 0;
  });

  test('explicit mutation evidence advances the mutation revision', () {
    final notification =
        jsonDecode('{"type":"flash_done","confirmed_mutation":true}')
            as Map<String, dynamic>;
    publishRefreshForAppEvent('notification', notification);

    expect(dataRevision.value, 1);
    expect(dataMutationRevision.value, 1);
    expect(dataLibraryCatchUpRevision.value, 0);
  });

  test(
    'task completion notifications publish their persisted asset updates',
    () {
      publishRefreshForAppEvent('notification', const {'type': 'task_done'});
      expect(dataMutationRevision.value, 0);

      publishRefreshForAppEvent('notification', const {
        'type': 'task_failed',
        'mutation_receipt': {'confirmed_mutation': true},
      });
      expect(dataMutationRevision.value, 1);
    },
  );

  test('capture status Q&A and no-record completion stay refresh-only', () {
    publishRefreshForAppEvent('capture', const {'session_id': 'session-1'});
    publishRefreshForAppEvent('flash_file_status', const {
      'status': 'done',
      'result_count': 0,
    });
    publishRefreshForAppEvent('session_changed', const {
      'session_id': 'session-1',
      'reason': 'title_changed',
    });
    for (final payload in const [
      {'type': 'flash_done', 'body': '长白山位于吉林省。'},
      {'type': 'flash_done', 'body': '没有生成记录'},
    ]) {
      publishRefreshForAppEvent('notification', payload);
    }

    expect(dataRevision.value, 5);
    expect(dataMutationRevision.value, 0);
  });

  test(
    'early status and ordinary notifications only request a legacy refresh',
    () {
      publishRefreshForAppEvent('flash_file_status', const {
        'status': 'processing_flash',
      });
      publishRefreshForAppEvent('notification', const {'type': 'reminder'});

      expect(dataRevision.value, 2);
      expect(dataMutationRevision.value, 0);
    },
  );
}
