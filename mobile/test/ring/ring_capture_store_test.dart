import 'dart:convert';

import 'package:eureka/ring/ring_capture_store.dart';
import 'package:eureka/ring/ring_capture_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('store restores only the authenticated users tasks', () async {
    final store = SharedPreferencesRingCaptureStore();
    await store.upsert('user-a', _ringTask(id: 'a', userId: 'user-a'));
    await store.upsert('user-b', _ringTask(id: 'b', userId: 'user-b'));

    expect((await store.load('user-a')).map((task) => task.id), ['a']);
    expect((await store.load('user-b')).map((task) => task.id), ['b']);
  });

  test(
    'upsert replaces by task id and remove rewrites the user list',
    () async {
      final store = SharedPreferencesRingCaptureStore();
      await store.upsert('user-a', _ringTask(id: 'a', userId: 'user-a'));
      await store.upsert(
        'user-a',
        _ringTask(id: 'a', userId: 'user-a', stage: RingCaptureStage.accepted),
      );

      expect(await store.load('user-a'), [
        isA<RingCaptureTask>().having(
          (task) => task.stage,
          'stage',
          RingCaptureStage.accepted,
        ),
      ]);

      await store.remove('user-a', 'a');
      expect(await store.load('user-a'), isEmpty);
    },
  );

  test(
    'load ignores malformed entries without rewriting persisted JSON',
    () async {
      final valid = _ringTask(id: 'valid', userId: 'user-a').toJson();
      final stored = jsonEncode([
        {'id': 'broken'},
        valid,
      ]);
      SharedPreferences.setMockInitialValues({
        'ring_capture_tasks_v1:user-a': stored,
      });
      final store = SharedPreferencesRingCaptureStore();

      expect((await store.load(' user-a ')).map((task) => task.id), ['valid']);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('ring_capture_tasks_v1:user-a'), stored);
    },
  );

  test('store rejects empty scope and cross-user tasks', () async {
    final store = SharedPreferencesRingCaptureStore();

    await expectLater(store.load('  '), throwsArgumentError);
    await expectLater(
      store.upsert('user-a', _ringTask(id: 'b', userId: 'user-b')),
      throwsArgumentError,
    );
  });
}

RingCaptureTask _ringTask({
  required String id,
  required String userId,
  RingCaptureStage stage = RingCaptureStage.recording,
}) {
  return RingCaptureTask(
    id: id,
    userId: userId,
    deviceId: 'AA:BB',
    stage: stage,
    startedAt: DateTime.utc(2026, 8, 11, 0, 30),
    updatedAt: DateTime.utc(2026, 8, 11, 0, 31),
  );
}
