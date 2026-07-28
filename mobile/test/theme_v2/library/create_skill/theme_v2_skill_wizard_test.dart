import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/create_skill_action.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_wizard_controller.dart';
import 'package:eureka/theme_v2/library/create_skill/theme_v2_skill_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Library launch opens the V2 describe wizard without a bridge', (
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
    expect(find.text('想记录点什么？'), findsOneWidget);
    expect(find.text('开始描述'), findsNothing);
  });

  testWidgets('wizard starts directly on the describe sheet', (tester) async {
    final repository = _WidgetRepository();
    final controller = SkillWizardController(repository: repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('想记录点什么？'), findsOneWidget);
    expect(find.text('开始描述'), findsNothing);
    expect(
      find.byKey(const ValueKey('skill-wizard-description')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('AI 生成技能'), findsOneWidget);
  });

  testWidgets('suggestion generates preview and confirm creates once', (
    tester,
  ) async {
    final repository = _WidgetRepository();
    final controller = SkillWizardController(repository: repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.text('跑步训练记录'));
    await tester.tap(find.bySemanticsLabel('AI 生成技能'));
    await tester.pumpAndSettle();

    expect(find.text('确认技能'), findsOneWidget);
    expect(find.text('跑步记录'), findsWidgets);
    expect(find.text('跑步日期'), findsOneWidget);
    expect(find.text('occurred_date'), findsOneWidget);
    expect(find.bySemanticsLabel('创建技能'), findsOneWidget);

    await tester.ensureVisible(find.bySemanticsLabel('创建技能'));
    await tester.tap(find.bySemanticsLabel('创建技能'));
    await tester.pumpAndSettle();
    expect(repository.confirmBodies, hasLength(1));
  });

  testWidgets('questions remain in the same sheet and preserve the prompt', (
    tester,
  ) async {
    final repository = _WidgetRepository(clarifyFirst: true);
    final controller = SkillWizardController(repository: repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.enterText(
      find.byKey(const ValueKey('skill-wizard-description')),
      '记录训练',
    );
    await tester.tap(find.bySemanticsLabel('AI 生成技能'));
    await tester.pumpAndSettle();
    expect(find.text('再补充几点'), findsOneWidget);
    expect(find.text('多久记录一次？'), findsOneWidget);

    await tester.tap(find.text('每天'));
    await tester.tap(find.bySemanticsLabel('生成技能预览'));
    await tester.pumpAndSettle();
    expect(find.text('确认技能'), findsOneWidget);
    expect(controller.description, '记录训练');
  });

  testWidgets('360px keyboard and large text do not overflow', (tester) async {
    final controller = SkillWizardController(repository: _WidgetRepository());
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
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

Future<void> _pump(
  WidgetTester tester,
  SkillWizardController controller, {
  Size size = const Size(411, 960),
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
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
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ThemeV2SkillWizardSheet(controller: controller),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
