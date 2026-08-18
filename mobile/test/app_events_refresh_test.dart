import 'package:eureka/app_events.dart';
import 'package:eureka/data_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    dataRevision.value = 0;
    dataMutationRevision.value = 0;
  });

  test('flash_done publishes a mutation after the derived-assets contract', () {
    publishRefreshForAppEvent('notification', const {'type': 'flash_done'});

    expect(dataRevision.value, 1);
    expect(dataMutationRevision.value, 1);
  });

  test(
    'task completion notifications publish their persisted asset updates',
    () {
      publishRefreshForAppEvent('notification', const {'type': 'task_done'});
      expect(dataMutationRevision.value, 1);

      publishRefreshForAppEvent('notification', const {'type': 'task_failed'});
      expect(dataMutationRevision.value, 2);
    },
  );

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
