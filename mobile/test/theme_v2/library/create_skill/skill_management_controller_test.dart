import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_configuration_repository.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_management_controller.dart';

void main() {
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

class _FakeRepository implements SkillManagementRepository {
  _FakeRepository(this.skill, {this.assetCount = 0});

  final ConfigurableSkill skill;
  final int assetCount;
  Map<String, dynamic>? savedSchema;
  bool deleted = false;

  @override
  Future<ConfigurableSkill> load(String userSkillId) async => skill;

  @override
  Future<ConfigurableSkill> save(
    String userSkillId,
    SkillManagementDraft draft,
  ) async {
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
