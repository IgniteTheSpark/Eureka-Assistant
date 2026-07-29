import 'dart:io';

import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_configuration_repository.dart';
import 'package:eureka/theme_v2/library/create_skill/skill_wizard_controller.dart';
import 'package:eureka/theme_v2/library/create_skill/theme_v2_skill_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surface = ValueKey('skill-builder-golden-surface');

  setUpAll(() async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'))).load();
    await (FontLoader('Geist Mono')..addFont(
          rootBundle.load('assets/fonts/GeistMono/GeistMono-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();

    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    if (pingFang.existsSync()) {
      await (FontLoader(
        'PingFang SC',
      )..addFont(pingFang.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  Future<void> pumpGolden(
    WidgetTester tester, {
    required Brightness brightness,
    required Widget child,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 960);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(brightness),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: RepaintBoundary(key: surface, child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('Describe 411 $suffix', (tester) async {
      final controller = SkillWizardController(
        repository: _GoldenSkillRepository(),
      );
      addTearDown(controller.dispose);

      await pumpGolden(
        tester,
        brightness: brightness,
        child: ThemeV2SkillWizardSheet(controller: controller, onClose: () {}),
      );

      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/skill-builder-describe-411-$suffix.png'),
      );
    });

    testWidgets('Fields 411 $suffix', (tester) async {
      final controller = await _generatedController();
      addTearDown(controller.dispose);

      await pumpGolden(
        tester,
        brightness: brightness,
        child: ThemeV2SkillWizardSheet(controller: controller, onClose: () {}),
      );

      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/skill-builder-fields-411-$suffix.png'),
      );
    });

    testWidgets('Card 411 $suffix', (tester) async {
      final controller = await _generatedController();
      controller.goToCard();
      addTearDown(controller.dispose);

      await pumpGolden(
        tester,
        brightness: brightness,
        child: ThemeV2SkillWizardSheet(controller: controller, onClose: () {}),
      );

      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/skill-builder-card-411-$suffix.png'),
      );
    });

    testWidgets('Card configuration 411 $suffix', (tester) async {
      final controller = SkillCardConfigurationController(
        repository: _GoldenConfigurationRepository(),
        userSkillId: 'skill-running',
      );
      addTearDown(controller.dispose);

      await pumpGolden(
        tester,
        brightness: brightness,
        child: ThemeV2SkillWizardSheet.configuration(
          controller: controller,
          onClose: () {},
        ),
      );

      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/card-display-settings-411-$suffix.png'),
      );
    });
  }
}

Future<SkillWizardController> _generatedController() async {
  final controller = SkillWizardController(
    repository: _GoldenSkillRepository(),
  );
  controller.setDescription('记录每次跑步的日期、距离、配速和感受');
  await controller.generate();
  return controller;
}

class _GoldenSkillRepository implements SkillWizardRepository {
  @override
  Future<Map<String, dynamic>> draft(Map<String, dynamic> body) async {
    return {
      'draft': {
        'name': 'running_log',
        'display_name': '跑步记录',
        'payload_schema': {
          'occurred_date': {
            'type': 'date',
            'label': '跑步日期',
            'required': true,
            'description': '本次训练发生的日期',
          },
          'distance': {
            'type': 'number',
            'label': '距离',
            'required': true,
            'description': '本次跑步公里数',
          },
          'notes': {
            'type': 'string',
            'label': '感受',
            'description': '训练中的身体与情绪感受',
          },
        },
        'render_spec': {
          'icon': '跑',
          'card_layout': 'horizontal',
          'primary_field': 'distance',
          'secondary_field': 'occurred_date',
          'meta_fields': [
            {'field': 'notes'},
          ],
        },
        'sample_payload': {
          'occurred_date': '2026-07-29',
          'distance': 5.2,
          'notes': '轻松跑，状态很好',
        },
      },
    };
  }

  @override
  Future<void> confirm(Map<String, dynamic> body) async {}
}

class _GoldenConfigurationRepository implements SkillConfigurationRepository {
  @override
  Future<ConfigurableSkill> load(String userSkillId) async {
    return const ConfigurableSkill(
      userSkillId: 'skill-running',
      name: 'running_log',
      displayName: '跑步记录',
      payloadSchema: {
        'distance': {'type': 'number', 'label': '距离'},
        'occurred_date': {'type': 'date', 'label': '跑步日期'},
        'notes': {'type': 'string', 'label': '感受'},
      },
      renderSpec: {
        'icon': '跑',
        'card_layout': 'horizontal',
        'primary_field': 'distance',
        'secondary_field': 'occurred_date',
        'meta_fields': [
          {'field': 'notes'},
        ],
      },
      samplePayload: {
        'distance': 5.2,
        'occurred_date': '2026-07-29',
        'notes': '轻松跑，状态很好',
      },
    );
  }

  @override
  Future<void> saveCardDisplay(
    String userSkillId,
    CardDisplayConfig config,
    Map<String, dynamic> originalRenderSpec,
  ) async {}
}
