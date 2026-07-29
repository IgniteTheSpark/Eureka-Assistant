import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:eureka/theme_v2/asset/card_field_selection.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changing primary removes it from the secondary order', () {
    final controller = CardFieldSelectionController(
      fields: _fields,
      config: CardDisplayConfig(
        primaryFieldId: 'title',
        secondaryFieldIds: const ['city', 'date'],
      ),
    );
    addTearDown(controller.dispose);

    controller.selectPrimary('city');

    expect(controller.config.primaryFieldId, 'city');
    expect(controller.config.secondaryFieldIds, ['date']);
    expect(controller.secondaryOrder('date'), 1);
  });

  test('secondary activation order is stable and capped at three', () {
    final controller = CardFieldSelectionController(
      fields: _fields,
      config: CardDisplayConfig(primaryFieldId: 'title'),
    );
    addTearDown(controller.dispose);

    expect(controller.toggleSecondary('city'), isTrue);
    expect(controller.toggleSecondary('date'), isTrue);
    expect(controller.toggleSecondary('score'), isTrue);
    expect(controller.toggleSecondary('venue'), isFalse);

    expect(controller.config.secondaryFieldIds, ['city', 'date', 'score']);
    expect(controller.secondaryOrder('city'), 1);
    expect(controller.secondaryOrder('score'), 3);
    expect(controller.errorMessage, '次要字段最多选择 3 个');

    expect(controller.toggleSecondary('date'), isTrue);
    expect(controller.toggleSecondary('venue'), isTrue);
    expect(controller.config.secondaryFieldIds, ['city', 'score', 'venue']);
  });

  test('primary field can never be enabled as secondary', () {
    final controller = CardFieldSelectionController(
      fields: _fields,
      config: CardDisplayConfig(primaryFieldId: 'title'),
    );
    addTearDown(controller.dispose);

    expect(controller.toggleSecondary('title'), isFalse);
    expect(controller.config.secondaryFieldIds, isEmpty);
  });

  testWidgets(
    'selector renders every field once with visible activation order',
    (tester) async {
      final controller = CardFieldSelectionController(
        fields: _fields.take(4).toList(),
        config: CardDisplayConfig(
          primaryFieldId: 'title',
          secondaryFieldIds: const ['date', 'city'],
        ),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildThemeV2Theme(Brightness.light),
          home: Scaffold(body: CardFieldSelector(controller: controller)),
        ),
      );

      expect(find.byKey(const ValueKey('card-field-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-field-city')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-field-date')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-field-score')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('card-secondary-title')),
            )
            .onChanged,
        isNull,
      );
    },
  );
}

const _fields = [
  CardSelectableField(id: 'title', label: '标题', type: 'string'),
  CardSelectableField(id: 'city', label: '城市', type: 'string'),
  CardSelectableField(id: 'date', label: '日期', type: 'date'),
  CardSelectableField(id: 'score', label: '比分', type: 'string'),
  CardSelectableField(id: 'venue', label: '场地', type: 'string'),
];
