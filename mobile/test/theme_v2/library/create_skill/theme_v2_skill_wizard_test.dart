import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:eureka/theme_v2/library/create_skill_action.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_configuration_repository.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_wizard_controller.dart';
import 'package:eureka/theme_v2/library/create_skill/theme_v2_skill_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Library launch opens the V2 three-step builder directly', (
    tester,
  ) async {
    final repository = _WidgetRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showThemeV2CreateSkillLaunch(
                  context,
                  repository: repository,
                ),
                child: const Text('创建'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.byType(ThemeV2SkillWizardSheet), findsOneWidget);
    expect(find.text('Describe'), findsOneWidget);
    expect(find.text('Fields'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-describe-step')), findsOneWidget);
  });

  testWidgets('Describe clarification stays in the same visible step', (
    tester,
  ) async {
    final repository = _WidgetRepository(clarifyFirst: true);
    final controller = SkillWizardController(repository: repository);
    addTearDown(controller.dispose);
    await _pump(tester, ThemeV2SkillWizardSheet(controller: controller));

    await tester.enterText(
      find.byKey(const ValueKey('skill-wizard-description')),
      '记录训练',
    );
    await tester.tap(find.byKey(const ValueKey('skill-describe-generate')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skill-describe-step')), findsOneWidget);
    expect(find.text('多久记录一次？'), findsOneWidget);
    expect(find.text('Questions'), findsNothing);

    await tester.tap(find.text('每天'));
    await tester.tap(find.byKey(const ValueKey('skill-describe-generate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill-fields-step')), findsOneWidget);
  });

  testWidgets('Fields edits schema then Card creates with shared selector', (
    tester,
  ) async {
    final repository = _WidgetRepository();
    final controller = SkillWizardController(repository: repository);
    addTearDown(controller.dispose);
    await _pump(tester, ThemeV2SkillWizardSheet(controller: controller));

    await tester.tap(find.text('跑步训练记录'));
    await tester.tap(find.byKey(const ValueKey('skill-describe-generate')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skill-fields-step')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('skill-field-occurred_date')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('skill-add-field')));
    await tester.tap(find.byKey(const ValueKey('skill-add-field')));
    await tester.pump();
    expect(controller.fields, hasLength(4));

    await tester.tap(find.byKey(const ValueKey('skill-fields-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill-card-step')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-field-distance')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('skill-card-confirm')));
    await tester.pumpAndSettle();
    expect(repository.confirmBodies, hasLength(1));
  });

  testWidgets('existing-skill configuration opens directly at Card', (
    tester,
  ) async {
    final repository = _ConfigurationRepository();
    final controller = SkillCardConfigurationController(
      repository: repository,
      userSkillId: 'skill-running',
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      ThemeV2SkillWizardSheet.configuration(controller: controller),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skill-card-step')), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-fields-step')), findsNothing);
    expect(find.byKey(const ValueKey('skill-card-save')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('skill-card-save')));
    await tester.pumpAndSettle();
    expect(repository.saved, isTrue);
  });

  testWidgets('360px keyboard and large text do not overflow', (tester) async {
    final controller = SkillWizardController(repository: _WidgetRepository());
    addTearDown(controller.dispose);
    await _pump(
      tester,
      ThemeV2SkillWizardSheet(controller: controller),
      size: const Size(360, 800),
      textScaler: const TextScaler.linear(1.5),
      viewInsets: const EdgeInsets.only(bottom: 260),
    );

    await tester.enterText(
      find.byKey(const ValueKey('skill-wizard-description')),
      '这是一段用来验证窄屏和大字号键盘状态的长描述',
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const ValueKey('skill-wizard-sheet'))).bottom,
      lessThanOrEqualTo(800),
    );
  });
}

class _WidgetRepository implements SkillWizardRepository {
  _WidgetRepository({this.clarifyFirst = false});

  final bool clarifyFirst;
  var draftCalls = 0;
  final confirmBodies = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> draft(Map<String, dynamic> body) async {
    draftCalls++;
    if (clarifyFirst && draftCalls == 1) {
      return {
        'questions': [
          {
            'key': 'frequency',
            'prompt': '多久记录一次？',
            'type': 'choice',
            'options': ['每天', '每周'],
          },
        ],
      };
    }
    return {
      'draft': {
        'name': 'running_log',
        'display_name': '跑步记录',
        'payload_schema': {
          'occurred_date': {'type': 'date', 'label': '跑步日期'},
          'distance': {'type': 'number', 'label': '距离'},
          'notes': {'type': 'string', 'label': '备注'},
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
      },
    };
  }

  @override
  Future<void> confirm(Map<String, dynamic> body) async {
    confirmBodies.add(body);
  }
}

class _ConfigurationRepository implements SkillConfigurationRepository {
  bool saved = false;

  @override
  Future<ConfigurableSkill> load(String userSkillId) async {
    return const ConfigurableSkill(
      userSkillId: 'skill-running',
      name: 'running_log',
      displayName: '跑步记录',
      payloadSchema: {
        'distance': {'type': 'number', 'label': '距离'},
        'date': {'type': 'date', 'label': '日期'},
      },
      renderSpec: {
        'icon': '🏃',
        'primary_field': 'distance',
        'secondary_field': 'date',
      },
      samplePayload: {'distance': 5.2, 'date': '2026-07-29'},
    );
  }

  @override
  Future<void> saveCardDisplay(
    String userSkillId,
    CardDisplayConfig config,
    Map<String, dynamic> originalRenderSpec,
  ) async {
    saved = true;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(411, 960),
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        devicePixelRatio: 1,
        textScaler: textScaler,
        viewInsets: viewInsets,
      ),
      child: MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}
