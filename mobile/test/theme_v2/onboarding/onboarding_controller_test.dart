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
  group('custom category', () {
    test('catalog always exposes a custom category card', () async {
      final repo = FakeOnboardingRepository(categories: [_runningCategory]);
      final controller = OnboardingController(repository: repo);
      await controller.loadCatalog();
      expect(controller.categories.map((c) => c['id']), contains('custom'));
      expect(controller.isCustomCategory, isFalse);
    });

    test('custom name and fields round-trip to the API', () async {
      final repo = FakeOnboardingRepository();
      final controller = OnboardingController(repository: repo);
      await controller.loadCatalog();

      controller.selectCategory('custom');
      expect(controller.isCustomCategory, isTrue);
      controller.setCustomCategoryName('睡眠');
      controller.addCustomField('起床时间');

      final ok = await controller.createSkill();
      expect(ok, isTrue);
      expect(repo.lastCategory, '睡眠');
      expect(repo.lastFields, [
        {'key': '起床时间', 'label': '起床时间', 'type': 'text'},
      ]);
    });

    test('blank custom category name is rejected', () async {
      final repo = FakeOnboardingRepository();
      final controller = OnboardingController(repository: repo);
      await controller.loadCatalog();

      controller.selectCategory('custom');
      controller.setCustomCategoryName('   ');
      controller.addCustomField('起床时间');

      final ok = await controller.createSkill();
      expect(ok, isFalse);
      expect(controller.error, '请填写自定义记录名称');
      expect(repo.lastCategory, isNull);
    });
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
      expect(controller.selectedFields.map((f) => f['key']), [
        'duration_min',
      ]);
    });

    test('user-added field defaults to text and rejects blank names', () async {
      final repo = FakeOnboardingRepository();
      final controller = OnboardingController(repository: repo);

      controller.addCustomField('  次数 ');
      expect(controller.selectedFields, [
        {'key': '次数', 'label': '次数', 'type': 'text'},
      ]);

      controller.addCustomField('   ');
      expect(controller.error, '字段名称不能为空');
      expect(controller.selectedFields.length, 1);
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

    test('previewFields expose editable extracted and missing values', () async {
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
    });

    test('confirmFromEdits coerces types and sends a non-empty payload',
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
        idempotencyKey: 'k-1',
      );
      expect(ok, isTrue);
      expect(repo.lastPayload, {'distance_km': 7, 'duration_min': 40});
      expect(repo.confirmCalls, 1);
    });

    test('all-empty payload is rejected client-side before any request',
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
        idempotencyKey: 'k-1',
      );
      expect(ok, isFalse);
      expect(controller.error, '请至少填写一个字段');
      expect(repo.confirmCalls, 0);
    });

    test('manual non-empty confirmation creates one asset via repository',
        () async {
      final repo = FakeOnboardingRepository();
      final controller = OnboardingController(repository: repo);
      seedExtractedFields(repo, controller);
      await controller.createSkill();

      repo.previewResponse = {
        'payload': null,
        'field_warnings': ['未能自动提取内容,请手动填写'],
        'manual_fields': [
          {'key': 'distance_km', 'label': '距离(公里)', 'type': 'text'},
        ],
      };
      await controller.runPreview('今天天气不错');
      expect(controller.previewPayload, isNull);
      expect(controller.previewFields.single['value'], '');

      final ok = await controller.confirmFromEdits(
        rawValues: {'distance_km': '3'},
        idempotencyKey: 'k-1',
      );
      expect(ok, isTrue);
      expect(repo.lastPayload, {'distance_km': '3'});
      expect(repo.confirmCalls, 1);
    });
  });
}
