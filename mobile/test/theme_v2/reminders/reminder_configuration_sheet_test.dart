import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/reminders/reminder_configuration_sheet.dart';
import 'package:eureka/theme_v2/reminders/reminder_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes missing, duplicate, and disabled reminder preferences', () {
    expect(normalizeReminderOffsets(null), [15]);
    expect(normalizeReminderOffsets([60, 15, 60, 0]), [0, 15, 60]);
    expect(normalizeReminderOffsets([]), isEmpty);
    expect(formatReminderSummary([]), '不提醒');
    expect(formatReminderSummary([0, 15, 60]), '开始时、提前 15 分钟、提前 1 小时');
  });

  testWidgets('multi-selects presets and returns a sorted result', (
    tester,
  ) async {
    final result = await _open(
      tester,
      initialOffsets: null,
      interact: () async {
        expect(_checked(tester, 15), isTrue);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('reminder-option-5')))
              .height,
          greaterThanOrEqualTo(44),
        );
        await tester.tap(find.byKey(const ValueKey('reminder-option-15')));
        await tester.tap(find.byKey(const ValueKey('reminder-option-5')));
        await tester.tap(find.byKey(const ValueKey('reminder-option-60')));
        await tester.tap(find.byKey(const ValueKey('reminder-save')));
      },
    );

    expect(result, [5, 60]);
  });

  testWidgets('no reminders clears every selected offset', (tester) async {
    final result = await _open(
      tester,
      initialOffsets: const [5, 15, 60],
      interact: () async {
        await tester.tap(find.byKey(const ValueKey('reminder-option-none')));
        await tester.tap(find.byKey(const ValueKey('reminder-save')));
      },
    );

    expect(result, isEmpty);
  });

  testWidgets('adds a custom minute offset without dropping presets', (
    tester,
  ) async {
    final result = await _open(
      tester,
      initialOffsets: const [15],
      interact: () async {
        await tester.tap(find.byKey(const ValueKey('reminder-option-custom')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('reminder-custom-input')),
          '90',
        );
        await tester.tap(find.byKey(const ValueKey('reminder-custom-add')));
        await tester.tap(find.byKey(const ValueKey('reminder-save')));
      },
    );

    expect(result, [15, 90]);
  });

  testWidgets('cancel keeps the caller unchanged', (tester) async {
    final result = await _open(
      tester,
      initialOffsets: const [30],
      interact: () async {
        await tester.tap(find.byKey(const ValueKey('reminder-cancel')));
      },
    );

    expect(result, isNull);
  });
}

bool _checked(WidgetTester tester, int minutes) =>
    tester
        .widget<CheckboxListTile>(
          find.descendant(
            of: find.byKey(ValueKey('reminder-option-$minutes')),
            matching: find.byType(CheckboxListTile),
          ),
        )
        .value ??
    false;

Future<List<int>?> _open(
  WidgetTester tester, {
  required List<int>? initialOffsets,
  required Future<void> Function() interact,
}) async {
  List<int>? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showReminderConfigurationSheet(
                context,
                initialOffsets: initialOffsets,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await interact();
  await tester.pumpAndSettle();
  return result;
}
