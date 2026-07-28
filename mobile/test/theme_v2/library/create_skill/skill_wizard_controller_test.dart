import 'dart:async';

import 'package:eureka/theme_v2/library/create_skill/skill_wizard_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describe validates locally and maps clarify questions', () async {
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
      ],
    );
    final controller = SkillWizardController(repository: repository);
    addTearDown(controller.dispose);

    expect(await controller.generate(), isFalse);
    expect(controller.errorMessage, '先描述一下你想记录什么');

    controller.setDescription('记录跑步');
    expect(await controller.generate(), isTrue);

    expect(controller.stage, SkillWizardStage.questions);
    expect(controller.questions.single.key, 'frequency');
    expect(controller.questions.single.options, ['每天', '每周']);
    expect(repository.draftBodies.single, {'description': '记录跑步'});
  });

  test(
    'clarify answers feed the mature draft contract and open preview',
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
      controller.setDescription('记录跑步');
      await controller.generate();

      controller.answer('frequency', '每天');
      expect(await controller.generate(), isTrue);

      expect(controller.stage, SkillWizardStage.preview);
      expect(controller.displayName, '跑步记录');
      expect(controller.icon, '🏃');
      expect(controller.fields.map((field) => field.key), [
        'occurred_date',
        'distance',
        'notes',
      ]);
      expect(repository.draftBodies.last, {
        'description': '记录跑步',
        'answers': [
          {'key': 'frequency', 'value': '每天'},
        ],
      });
    },
  );

  test('preview slots stay unique and info is capped at three', () async {
    final controller = SkillWizardController(
      repository: _FakeSkillWizardRepository(
        draftResponses: [
          {
            'draft': _draft(
              schema: {
                'first': {'type': 'string', 'label': '第一'},
                'second': {'type': 'string', 'label': '第二'},
                'third': {'type': 'string', 'label': '第三'},
                'fourth': {'type': 'string', 'label': '第四'},
                'fifth': {'type': 'string', 'label': '第五'},
              },
              renderSpec: {
                'icon': '✨',
                'card_layout': 'horizontal',
                'primary_field': 'first',
                'secondary_field': 'second',
                'meta_fields': [
                  {'field': 'third'},
                  {'field': 'fourth'},
                  {'field': 'fifth'},
                ],
              },
            ),
          },
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.setDescription('自定义');
    await controller.generate();

    controller.assignSlot('second', SkillFieldSlot.primary);
    expect(controller.slotOf('second'), SkillFieldSlot.primary);
    expect(controller.slotOf('first'), SkillFieldSlot.hidden);

    controller.assignSlot('first', SkillFieldSlot.info);
    expect(controller.slotOf('first'), SkillFieldSlot.hidden);
    expect(controller.errorMessage, contains('最多'));

    controller.assignSlot('third', SkillFieldSlot.hidden);
    controller.assignSlot('first', SkillFieldSlot.info);
    expect(controller.slotOf('first'), SkillFieldSlot.info);
  });

  test('confirm sends edited identity and composed render spec once', () async {
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
    controller
      ..setDisplayName('我的跑步')
      ..setIcon('⚡')
      ..assignSlot('notes', SkillFieldSlot.secondary);

    expect(await controller.confirm(), isTrue);
    expect(controller.stage, SkillWizardStage.complete);
    expect(created, 1);
    expect(repository.confirmBodies.single, {
      'name': 'running_log',
      'display_name': '我的跑步',
      'payload_schema': _draft()['payload_schema'],
      'render_spec': {
        'card_layout': 'horizontal',
        'icon': '⚡',
        'accent_color': 'neutral',
        'primary_field': 'distance',
        'secondary_field': 'notes',
        'meta_fields': const [],
      },
      'chat_starters': ['记录今天跑步'],
    });

    expect(await controller.confirm(), isFalse);
    expect(repository.confirmBodies, hasLength(1));
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
    expect(controller.stage, SkillWizardStage.preview);
  });
}

Map<String, dynamic> _draft({
  String displayName = '跑步记录',
  Map<String, dynamic>? schema,
  Map<String, dynamic>? renderSpec,
}) {
  final payloadSchema =
      schema ??
      {
        'id': {'type': 'uuid'},
        'occurred_date': {'type': 'date', 'label': '跑步日期'},
        'distance': {'type': 'number', 'label': '距离'},
        'notes': {'type': 'string', 'label': '备注', 'long': true},
      };
  return {
    'name': 'running_log',
    'display_name': displayName,
    'payload_schema': payloadSchema,
    'render_spec':
        renderSpec ??
        {
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
