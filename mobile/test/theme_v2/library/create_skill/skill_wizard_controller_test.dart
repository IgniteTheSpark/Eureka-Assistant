import 'dart:async';

import 'package:eureka/theme_v2/library/create_skill/skill_wizard_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'clarification remains inside Describe and feeds draft generation',
    () async {
      final repository = _FakeSkillWizardRepository(
        draftResponses: [
          {
            'questions': [
              {
                'key': 'frequency',
                'prompt': '多久记录一次？',
                'type': 'choice',
                'options': ['每天', '每周'],
              },
            ],
          },
          {'draft': _draft()},
        ],
      );
      final controller = SkillWizardController(repository: repository);
      addTearDown(controller.dispose);

      expect(await controller.generate(), isFalse);
      expect(controller.errorMessage, '先描述一下你想记录什么');

      controller.setDescription('记录跑步');
      expect(await controller.generate(), isTrue);
      expect(controller.stage, SkillWizardStage.describe);
      expect(controller.questions.single.key, 'frequency');

      controller.answer('frequency', '每天');
      expect(await controller.generate(), isTrue);
      expect(controller.stage, SkillWizardStage.fields);
      expect(repository.draftBodies.last, {
        'description': '记录跑步',
        'answers': [
          {'key': 'frequency', 'value': '每天'},
        ],
      });
    },
  );

  test(
    'generated schema becomes editable field drafts with meaning and required',
    () async {
      final controller = SkillWizardController(
        repository: _FakeSkillWizardRepository(
          draftResponses: [
            {'draft': _draft()},
          ],
        ),
      );
      addTearDown(controller.dispose);
      controller.setDescription('记录跑步');
      await controller.generate();

      expect(controller.stage, SkillWizardStage.fields);
      expect(controller.fields.map((field) => field.key), [
        'occurred_date',
        'distance',
        'notes',
      ]);
      expect(controller.fields[1].meaning, '本次跑步总距离');
      expect(controller.fields[1].required, isTrue);
      expect(controller.payloadSchema['id'], {'type': 'uuid'});
    },
  );

  test(
    'Fields supports edit add remove and reorder with stable field ids',
    () async {
      final controller = await _generatedController();
      addTearDown(controller.dispose);

      controller.updateField(
        'distance',
        key: 'kilometers',
        label: '公里',
        meaning: '总距离',
        required: true,
      );
      final added = controller.addField(
        key: 'weather',
        label: '天气',
        type: 'string',
        meaning: '跑步天气',
      );
      controller.moveField(controller.fields.length - 1, 0);
      controller.removeField('notes');

      expect(added.key, 'weather');
      expect(controller.fields.map((field) => field.key), [
        'weather',
        'occurred_date',
        'kilometers',
      ]);
      expect(controller.payloadSchema.keys, [
        'id',
        'weather',
        'occurred_date',
        'kilometers',
      ]);
      expect(controller.payloadSchema['kilometers'], {
        'type': 'number',
        'label': '公里',
        'description': '总距离',
        'required': true,
      });
      expect(controller.samplePayload['kilometers'], 5.2);
      expect(controller.samplePayload.containsKey('distance'), isFalse);
    },
  );

  test(
    'Card uses shared selection and confirm emits compatible render spec',
    () async {
      final repository = _FakeSkillWizardRepository(
        draftResponses: [
          {'draft': _draft()},
        ],
      );
      var created = 0;
      final controller = SkillWizardController(
        repository: repository,
        onCreated: () => created++,
      );
      addTearDown(controller.dispose);
      controller.setDescription('记录跑步');
      await controller.generate();
      expect(controller.goToCard(), isTrue);
      expect(controller.stage, SkillWizardStage.card);

      controller
        ..setDisplayName('我的跑步')
        ..setIcon('⚡');
      controller.cardSelection!.selectPrimary('notes');

      expect(await controller.confirm(), isTrue);
      expect(controller.completed, isTrue);
      expect(created, 1);
      expect(repository.confirmBodies, hasLength(1));
      final body = repository.confirmBodies.single;
      expect(body['display_name'], '我的跑步');
      expect(body['payload_schema'], controller.payloadSchema);
      expect(body['render_spec'], {
        'icon': '⚡',
        'card_layout': 'horizontal',
        'primary_field': 'notes',
        'secondary_field': 'occurred_date',
        'meta_fields': const [],
        'card_display': {
          'primary_field_id': 'notes',
          'secondary_field_ids': ['occurred_date'],
        },
      });
      expect(await controller.confirm(), isFalse);
    },
  );

  test('field validation blocks duplicate keys before Card', () async {
    final controller = await _generatedController();
    addTearDown(controller.dispose);

    controller.updateField('notes', key: 'distance');

    expect(controller.goToCard(), isFalse);
    expect(controller.stage, SkillWizardStage.fields);
    expect(controller.errorMessage, '字段 key 不能重复');
  });

  test('stale draft response cannot replace the latest description', () async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final repository = _ControlledDraftRepository([first, second]);
    final controller = SkillWizardController(repository: repository);
    addTearDown(controller.dispose);

    controller.setDescription('旧描述');
    final oldRequest = controller.generate();
    controller.setDescription('新描述');
    final newRequest = controller.generate();
    second.complete({'draft': _draft(displayName: '新技能')});
    expect(await newRequest, isTrue);
    first.complete({'draft': _draft(displayName: '旧技能')});
    expect(await oldRequest, isFalse);

    expect(controller.displayName, '新技能');
    expect(controller.stage, SkillWizardStage.fields);
  });
}

Future<SkillWizardController> _generatedController() async {
  final controller = SkillWizardController(
    repository: _FakeSkillWizardRepository(
      draftResponses: [
        {'draft': _draft()},
      ],
    ),
  );
  controller.setDescription('记录跑步');
  await controller.generate();
  return controller;
}

Map<String, dynamic> _draft({String displayName = '跑步记录'}) {
  return {
    'name': 'running_log',
    'display_name': displayName,
    'payload_schema': {
      'id': {'type': 'uuid'},
      'occurred_date': {
        'type': 'date',
        'label': '跑步日期',
        'description': '实际跑步日期',
      },
      'distance': {
        'type': 'number',
        'label': '距离',
        'description': '本次跑步总距离',
        'required': true,
      },
      'notes': {'type': 'string', 'label': '备注', 'long': true},
    },
    'render_spec': {
      'icon': '🏃',
      'card_layout': 'horizontal',
      'primary_field': 'distance',
      'secondary_field': 'occurred_date',
      'meta_fields': [
        {'field': 'notes'},
      ],
    },
    'sample_payload': {
      'occurred_date': '2026-07-28',
      'distance': 5.2,
      'notes': '轻松跑',
    },
    'chat_starters': ['记录今天跑步'],
  };
}

class _FakeSkillWizardRepository implements SkillWizardRepository {
  _FakeSkillWizardRepository({required this.draftResponses});

  final List<Map<String, dynamic>> draftResponses;
  final draftBodies = <Map<String, dynamic>>[];
  final confirmBodies = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> draft(Map<String, dynamic> body) async {
    draftBodies.add(body);
    return draftResponses.removeAt(0);
  }

  @override
  Future<void> confirm(Map<String, dynamic> body) async {
    confirmBodies.add(body);
  }
}

class _ControlledDraftRepository implements SkillWizardRepository {
  _ControlledDraftRepository(this.responses);

  final List<Completer<Map<String, dynamic>>> responses;
  var index = 0;

  @override
  Future<Map<String, dynamic>> draft(Map<String, dynamic> body) {
    return responses[index++].future;
  }

  @override
  Future<void> confirm(Map<String, dynamic> body) async {}
}
