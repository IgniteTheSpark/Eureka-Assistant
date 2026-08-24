import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/onboarding/onboarding_controller.dart';
import 'package:eureka/theme_v2/onboarding/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_test_helpers.dart';

const _runningCategory = <String, dynamic>{
  'id': 'running',
  'label': '跑步',
  'description': '记录距离、时长与地点',
  'fields': <Map<String, dynamic>>[
    {'key': 'distance_km', 'label': '距离(公里)', 'type': 'number'},
    {'key': 'duration_min', 'label': '时长(分钟)', 'type': 'duration'},
  ],
};

const _catalogCategories = <Map<String, dynamic>>[
  _runningCategory,
  {
    'id': 'drinking_water',
    'label': '喝水',
    'description': '记录饮水',
    'fields': <Map<String, dynamic>>[],
  },
  {
    'id': 'baby_feeding',
    'label': '宝宝喂养',
    'description': '记录喂养',
    'fields': <Map<String, dynamic>>[],
  },
  {
    'id': 'dancing',
    'label': '跳舞',
    'description': '记录跳舞',
    'fields': <Map<String, dynamic>>[],
  },
];

Widget _host(OnboardingController controller) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    theme: buildThemeV2Theme(Brightness.light),
    home: OnboardingPage(controller: controller),
  );
}

void main() {
  testWidgets(
    'curated category and fields have back/skip with no custom input',
    (tester) async {
      final repo = FakeOnboardingRepository(categories: _catalogCategories);
      repo.previewResponse = {
        'payload': {'distance_km': 5.0},
        'field_warnings': const <String>[],
        'manual_fields': const <Map<String, dynamic>>[],
      };
      final controller = OnboardingController(repository: repo);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      // Value screen -> category.
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();

      expect(find.text('跑步'), findsOneWidget);
      expect(find.text('喝水'), findsOneWidget);
      expect(find.text('宝宝喂养'), findsOneWidget);
      expect(find.text('跳舞'), findsOneWidget);
      expect(find.text('自定义记录'), findsNothing);
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);

      await tester.tap(find.text('跑步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('添加'), findsNothing);
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('请至少选择一个记录字段'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, '距离(公里)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(repo.lastCategory, 'running');
      expect(repo.lastFieldKeys, ['distance_km']);

      // Input screen.
      await tester.enterText(find.byType(TextField).first, '我今天跑了5公里');
      await tester.tap(find.text('识别并整理'));
      await tester.pumpAndSettle();

      // Preview: editable extracted value.
      expect(find.text('确认内容'), findsOneWidget);
      final editors = find.byType(TextField);
      expect(editors, findsOneWidget);
      expect(tester.widget<TextField>(editors).controller!.text, '5.0');
      await tester.enterText(editors, '6');
      await tester.tap(find.text('保存到首页'));
      await tester.pumpAndSettle();

      expect(repo.confirmCalls, 1);
      expect(repo.lastPayload, {'distance_km': 6});
    },
  );

  testWidgets('preview failure keeps typed source and exposes retry error', (
    tester,
  ) async {
    final repo = FakeOnboardingRepository(
      categories: [_runningCategory],
      failPreview: true,
    );
    final controller = OnboardingController(repository: repo);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跑步'));
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '距离(公里)'));
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    const source = '我今天跑了5公里';
    await tester.enterText(find.byType(TextField).first, source);
    await tester.tap(find.text('识别并整理'));
    await tester.pumpAndSettle();

    expect(find.text('提取失败，请重试或直接手动填写'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      source,
    );
  });

  testWidgets('all-empty confirmation is blocked in the preview screen', (
    tester,
  ) async {
    final repo = FakeOnboardingRepository(categories: [_runningCategory]);
    repo.previewResponse = {
      'payload': null,
      'field_warnings': ['未能自动提取内容,请手动填写'],
      'manual_fields': [
        {'key': 'distance_km', 'label': '距离(公里)', 'type': 'text'},
      ],
    };
    final controller = OnboardingController(repository: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跑步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '距离(公里)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '今天天气不错');
    await tester.tap(find.text('识别并整理'));
    await tester.pumpAndSettle();

    expect(find.text('确认内容'), findsOneWidget);
    await tester.tap(find.text('保存到首页'));
    await tester.pumpAndSettle();

    expect(find.text('请至少填写一个字段'), findsOneWidget);
    expect(repo.confirmCalls, 0);
    expect(controller.createdAssetId, isNull);
  });
}
