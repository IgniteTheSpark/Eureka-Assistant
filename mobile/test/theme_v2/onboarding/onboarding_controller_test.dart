import 'dart:async';

import 'package:eureka/theme_v2/onboarding/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_test_helpers.dart';

const _runningFields = <Map<String, dynamic>>[
  {'key': 'distance_km', 'label': '距离(公里)', 'type': 'number'},
  {'key': 'duration_min', 'label': '时长(分钟)', 'type': 'duration'},
];

const _runningCategory = <String, dynamic>{
  'id': 'running',
  'label': '跑步',
  'fields': _runningFields,
};

void main() {
  group('curated categories', () {
    test('catalog never injects a custom category', () async {
      final repo = FakeOnboardingRepository(categories: [_runningCategory]);
      final controller = OnboardingController(repository: repo);
      await controller.loadCatalog();
      expect(controller.categories.map((c) => c['id']), ['running']);
      expect(
        controller.categories.map((c) => c['id']),
        isNot(contains('custom')),
      );
    });

    test(
      'fallback contains all four curated categories and no custom entry',
      () async {
        final repo = FakeOnboardingRepository(failCatalog: true);
        final controller = OnboardingController(repository: repo);
        await controller.loadCatalog();

        expect(controller.categories.map((c) => c['id']), [
          'running',
          'drinking_water',
          'baby_feeding',
          'dancing',
        ]);
        expect(
          controller.categories.map((c) => c['id']),
          isNot(contains('custom')),
        );
      },
    );
  });

  group('field selection', () {
    test('suggested fields support multi-select and de-select', () async {
      final repo = FakeOnboardingRepository();
      final controller = OnboardingController(repository: repo);
      await controller.loadCatalog();

      controller.selectCategory('running');
      controller.toggleField(_runningFields[0]);
      controller.toggleField(_runningFields[1]);
      expect(controller.selectedFields.length, 2);

      controller.toggleField(_runningFields[0]);
      expect(controller.selectedFields.map((f) => f['key']), ['duration_min']);
    });

    test('create sends only selected field keys', () async {
      final repo = FakeOnboardingRepository(categories: [_runningCategory]);
      final controller = OnboardingController(repository: repo);
      await controller.loadCatalog();
      controller.selectCategory('running');
      controller.toggleField(_runningFields[1]);
      controller.toggleField(_runningFields[0]);

      expect(await controller.createSkill(), isTrue);
      expect(repo.lastCategory, 'running');
      expect(repo.lastFieldKeys, ['duration_min', 'distance_km']);
    });

    test('create is single-flight and notifies busy transitions', () async {
      final gate = Completer<void>();
      final repo = FakeOnboardingRepository(
        categories: [_runningCategory],
        createGate: gate,
      );
      final controller = OnboardingController(repository: repo);
      await controller.loadCatalog();
      controller.selectCategory('running');
      controller.toggleField(_runningFields[0]);
      final busyStates = <bool>[];
      controller.addListener(() => busyStates.add(controller.creatingSkill));

      final first = controller.createSkill();
      final second = controller.createSkill();
      expect(controller.creatingSkill, isTrue);
      expect(repo.createCalls, 1);
      gate.complete();

      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(controller.creatingSkill, isFalse);
      expect(busyStates, containsAllInOrder([true, false]));
    });
  });

  group('editable preview', () {
    void seedExtractedFields(
      FakeOnboardingRepository repo,
      OnboardingController controller,
    ) {
      controller.selectCategory('running');
      controller.toggleField(_runningFields[0]);
      controller.toggleField(_runningFields[1]);
    }

    test(
      'previewFields expose editable extracted and missing values',
      () async {
        final repo = FakeOnboardingRepository();
        final controller = OnboardingController(repository: repo);
        seedExtractedFields(repo, controller);
        await controller.createSkill();

        repo.previewResponse = {
          'payload': {'distance_km': 5.0},
          'field_warnings': ['未能从输入中识别「时长(分钟)」'],
          'manual_fields': const <Map<String, dynamic>>[],
        };
        await controller.runPreview('我今天沿着河边跑了5公里');

        final fields = controller.previewFields;
        expect(fields.length, 2);
        final km = fields.singleWhere((f) => f['key'] == 'distance_km');
        expect(km['value'], '5.0');
        expect(km['extracted'], isTrue);
        final duration = fields.singleWhere((f) => f['key'] == 'duration_min');
        expect(duration['value'], '');
        expect(duration['extracted'], isFalse);
      },
    );

    test(
      'confirmFromEdits coerces types and sends a non-empty payload',
      () async {
        final repo = FakeOnboardingRepository();
        final controller = OnboardingController(repository: repo);
        seedExtractedFields(repo, controller);
        await controller.createSkill();

        repo.previewResponse = {
          'payload': {'distance_km': 5.0},
          'field_warnings': const <String>[],
          'manual_fields': const <Map<String, dynamic>>[],
        };
        await controller.runPreview('x');

        final ok = await controller.confirmFromEdits(
          rawValues: {'distance_km': '7', 'duration_min': '40'},
        );
        expect(ok, isTrue);
        expect(repo.lastPayload, {'distance_km': 7, 'duration_min': 40});
        expect(repo.confirmCalls, 1);
      },
    );

    test(
      'all-empty payload is rejected client-side before any request',
      () async {
        final repo = FakeOnboardingRepository();
        final controller = OnboardingController(repository: repo);
        seedExtractedFields(repo, controller);
        await controller.createSkill();

        repo.previewResponse = {
          'payload': {'distance_km': 5.0},
          'field_warnings': const <String>[],
          'manual_fields': const <Map<String, dynamic>>[],
        };
        await controller.runPreview('x');

        final ok = await controller.confirmFromEdits(
          rawValues: {'distance_km': '   ', 'duration_min': ''},
        );
        expect(ok, isFalse);
        expect(controller.error, '请至少填写一个字段');
        expect(repo.confirmCalls, 0);
      },
    );

    test(
      'manual non-empty confirmation creates one asset via repository',
      () async {
        final repo = FakeOnboardingRepository();
        final controller = OnboardingController(repository: repo);
        seedExtractedFields(repo, controller);
        await controller.createSkill();

        repo.previewResponse = {
          'payload': null,
          'field_warnings': ['未能自动提取内容,请手动填写'],
          'manual_fields': [
            {'key': 'distance_km', 'label': '距离(公里)', 'type': 'number'},
          ],
        };
        await controller.runPreview('今天天气不错');
        expect(controller.previewPayload, isNull);
        expect(controller.previewFields.single['value'], '');

        final ok = await controller.confirmFromEdits(
          rawValues: {'distance_km': '3'},
        );
        expect(ok, isTrue);
        expect(repo.lastPayload, {'distance_km': 3});
        expect(repo.confirmCalls, 1);
      },
    );

    test(
      'same failed payload reuses UUID and changed payload rotates it',
      () async {
        final repo = FakeOnboardingRepository(failConfirm: true);
        final controller = OnboardingController(repository: repo);
        seedExtractedFields(repo, controller);
        await controller.createSkill();
        repo.previewResponse = {
          'payload': {'distance_km': 5.0},
          'field_warnings': const <String>[],
          'manual_fields': const <Map<String, dynamic>>[],
        };
        await controller.runPreview('x');

        expect(
          await controller.confirmFromEdits(
            rawValues: {'distance_km': '5', 'duration_min': '32'},
          ),
          isFalse,
        );
        expect(
          await controller.confirmFromEdits(
            rawValues: {'duration_min': '32', 'distance_km': '5'},
          ),
          isFalse,
        );
        expect(
          await controller.confirmFromEdits(
            rawValues: {'distance_km': '6', 'duration_min': '32'},
          ),
          isFalse,
        );

        expect(repo.confirmKeys[0], repo.confirmKeys[1]);
        expect(repo.confirmKeys[2], isNot(repo.confirmKeys[1]));
        expect(
          repo.confirmKeys.first,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      },
    );
  });
}
