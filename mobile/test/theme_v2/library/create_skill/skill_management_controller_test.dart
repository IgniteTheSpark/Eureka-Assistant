import 'package:eureka/theme_v2/asset/card_field_selection.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_configuration_repository.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_management_controller.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_management_sheet.dart';

void main() {
  testWidgets('custom management contains fields card display and deletion', (
    tester,
  ) async {
    final controller = SkillManagementController(
      repository: _FakeRepository(_multiFieldSkill()),
      userSkillId: 'tennis-id',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ThemeV2SkillManagementSheet(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('记录字段'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('卡片展示'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byType(CardFieldSelector), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('custom-skill-delete')), findsOneWidget);
  });

  testWidgets('failed management save keeps the draft available for retry', (
    tester,
  ) async {
    final repository = _FakeRepository(_multiFieldSkill())..failSave = true;
    final controller = SkillManagementController(
      repository: repository,
      userSkillId: 'tennis-id',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: ThemeV2SkillManagementSheet(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(ValueKey('skill-name-${controller.skill!.updatedAt}')),
      '室内网球',
    );
    controller.cardSelection!.selectPrimary('surface');

    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    expect(controller.displayName, '室内网球');
    expect(controller.cardSelection!.config.primaryFieldId, 'surface');

    repository.failSave = false;
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(repository.saved!.displayName, '室内网球');
    expect(repository.saved!.renderSpec['primary_field'], 'surface');
  });

  test(
    'existing keys and types stay locked while new fields stay optional',
    () async {
      final repository = _FakeRepository(_tennisSkill());
      final controller = SkillManagementController(
        repository: repository,
        userSkillId: 'tennis-id',
      );

      await controller.load();

      expect(controller.updateExistingKey('duration', 'minutes'), isFalse);
      expect(controller.updateExistingType('duration', 'string'), isFalse);
      controller.addField(key: 'location', label: '地点', type: 'string');
      expect(controller.setFieldHidden('duration', true), isTrue);
      expect(controller.fields.last.original, isFalse);
      expect(await controller.save(), isTrue);
      expect(repository.savedSchema?['required'], isEmpty);
      final properties = repository.savedSchema?['properties'] as Map;
      expect(properties['duration']['x-hidden'], isTrue);
      expect(properties['location']['type'], 'string');
    },
  );

  test(
    'preselects the saved card fields and saves them with field edits',
    () async {
      final repository = _FakeRepository(_multiFieldSkill());
      final controller = SkillManagementController(
        repository: repository,
        userSkillId: 'tennis-id',
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.cardSelection!.config.primaryFieldId, 'duration');
      expect(controller.cardSelection!.config.secondaryFieldIds, ['surface']);
      expect(controller.preview!.primaryValue, '时长');
      controller.addField(key: 'location', label: '地点', type: 'string');
      controller.cardSelection!.selectPrimary('location');
      expect(controller.preview!.primaryValue, '地点');
      controller.updateFieldLabel('surface', '室内场地');
      controller.cardSelection!.selectPrimary('surface');
      expect(controller.preview!.primaryValue, '室内场地');
      controller.cardSelection!.selectPrimary('location');
      expect(controller.cardSelection!.toggleSecondary('surface'), isTrue);
      expect(controller.cardSelection!.toggleSecondary('status'), isTrue);

      expect(await controller.save(), isTrue);
      expect(
        (repository.saved!.schema['properties'] as Map),
        contains('location'),
      );
      expect(repository.saved!.renderSpec['primary_field'], 'location');
      expect(repository.saved!.renderSpec['card_display'], {
        'primary_field_id': 'location',
        'secondary_field_ids': ['surface', 'status'],
      });
    },
  );

  test(
    'rebuilds selectable card fields after visibility and order edits',
    () async {
      final controller = SkillManagementController(
        repository: _FakeRepository(_multiFieldSkill()),
        userSkillId: 'tennis-id',
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.load();
      final replacedSelection = controller.cardSelection!;
      controller.reorderField(2, 0);

      expect(controller.cardSelection!.fields.map((field) => field.id), [
        'status',
        'duration',
        'surface',
      ]);
      expect(controller.cardSelection!.config.primaryFieldId, 'duration');
      expect(controller.cardSelection!.config.secondaryFieldIds, ['surface']);
      expect(controller.setFieldHidden('duration', true), isTrue);
      expect(controller.cardSelection!.fields.map((field) => field.id), [
        'status',
        'surface',
      ]);
      expect(controller.cardSelection!.config.primaryFieldId, 'status');
      expect(controller.cardSelection!.config.secondaryFieldIds, ['surface']);
      final notificationsBeforeStaleChange = notifications;
      expect(
        () => replacedSelection.selectPrimary('status'),
        throwsFlutterError,
      );
      expect(notifications, notificationsBeforeStaleChange);
    },
  );

  test('failed save retains field and card display edits in memory', () async {
    final repository = _FakeRepository(_multiFieldSkill())..failSave = true;
    final controller = SkillManagementController(
      repository: repository,
      userSkillId: 'tennis-id',
    );
    addTearDown(controller.dispose);

    await controller.load();
    controller.addField(key: 'location', label: '地点', type: 'string');
    controller.cardSelection!.selectPrimary('location');

    expect(await controller.save(), isFalse);
    expect(controller.fields.last.key, 'location');
    expect(controller.cardSelection!.config.primaryFieldId, 'location');
  });

  test('disposal detaches the card selection listener', () async {
    final controller = SkillManagementController(
      repository: _FakeRepository(_multiFieldSkill()),
      userSkillId: 'tennis-id',
    );
    await controller.load();
    final selection = controller.cardSelection!;

    controller.dispose();

    expect(() => selection.selectPrimary('surface'), throwsFlutterError);
  });

  test('loads deletion impact and deletes with the reported count', () async {
    final repository = _FakeRepository(_tennisSkill(), assetCount: 4);
    final controller = SkillManagementController(
      repository: repository,
      userSkillId: 'tennis-id',
    );

    await controller.load();
    expect(await controller.loadDeletionImpact(), 4);
    expect(await controller.deleteSkill(), 4);
    expect(repository.deleted, isTrue);
  });
}

ConfigurableSkill _tennisSkill() => ConfigurableSkill.fromJson({
  'id': 'tennis-id',
  'machine_name': 'tennis',
  'display_name': '网球记录',
  'description': '记录每次网球训练',
  'updated_at': '2026-08-18T08:00:00Z',
  'schema': {
    'type': 'object',
    'properties': {
      'duration': {'type': 'number', 'title': '时长'},
    },
    'required': <String>[],
  },
  'render_spec': <String, dynamic>{},
});

ConfigurableSkill _multiFieldSkill() => ConfigurableSkill.fromJson({
  'id': 'tennis-id',
  'machine_name': 'tennis',
  'display_name': '网球记录',
  'description': '记录每次网球训练',
  'updated_at': '2026-08-18T08:00:00Z',
  'schema': {
    'type': 'object',
    'properties': {
      'duration': {'type': 'number', 'title': '时长'},
      'surface': {'type': 'string', 'title': '场地'},
      'status': {'type': 'string', 'title': '状态'},
    },
    'required': <String>[],
  },
  'render_spec': {'primary_field': 'duration', 'secondary_field': 'surface'},
});

class _FakeRepository implements SkillManagementRepository {
  _FakeRepository(this.skill, {this.assetCount = 0});

  final ConfigurableSkill skill;
  final int assetCount;
  Map<String, dynamic>? savedSchema;
  SkillManagementDraft? saved;
  bool failSave = false;
  bool deleted = false;

  @override
  Future<ConfigurableSkill> load(String userSkillId) async => skill;

  @override
  Future<ConfigurableSkill> save(
    String userSkillId,
    SkillManagementDraft draft,
  ) async {
    if (failSave) throw StateError('offline');
    saved = draft;
    savedSchema = draft.schema;
    return skill;
  }

  @override
  Future<int> deletionImpact(String userSkillId) async => assetCount;

  @override
  Future<void> delete(String userSkillId) async {
    deleted = true;
  }
}
