import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/onboarding/onboarding_controller.dart';
import 'package:eureka/theme_v2/onboarding/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Widget _host(OnboardingController controller) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    theme: buildThemeV2Theme(Brightness.light),
    home: OnboardingPage(controller: controller),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('custom category with user-added field creates, edits, confirms',
      (tester) async {
    final repo = FakeOnboardingRepository(categories: [_runningCategory]);
    repo.previewResponse = {
      'payload': {'起床时间': '07:00'},
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

    // Select the custom category and type a name.
    await tester.tap(find.text('自定义记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '睡眠');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // Fields: add a custom field (no suggestions for custom category).
    await tester.enterText(find.byType(TextField).first, '起床时间');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('起床时间'), findsOneWidget);
    await tester.tap(find.text('创建记录类型'));
    await tester.pumpAndSettle();

    expect(repo.lastCategory, '睡眠');
    expect(repo.lastFields, [
      {'key': '起床时间', 'label': '起床时间', 'type': 'text'},
    ]);

    // Input screen.
    await tester.enterText(find.byType(TextField).first, '我今天七点起床');
    await tester.tap(find.text('识别并整理'));
    await tester.pumpAndSettle();

    // Preview: editable extracted value.
    expect(find.text('确认内容'), findsOneWidget);
    final editors = find.byType(TextField);
    expect(editors, findsOneWidget);
    expect(
      tester.widget<TextField>(editors).controller!.text,
      '07:00',
    );
    await tester.enterText(editors, '08:30');
    await tester.tap(find.text('保存到首页'));
    await tester.pumpAndSettle();

    expect(repo.confirmCalls, 1);
    expect(repo.lastPayload, {'起床时间': '08:30'});
  });

  testWidgets('all-empty confirmation is blocked in the preview screen',
      (tester) async {
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
    await tester.tap(find.text('创建记录类型'));
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
