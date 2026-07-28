import 'dart:async';

import 'package:eureka/pages/calendar_page.dart';
import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_mode_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarModeState', () {
    test('maps legacy timeline and invalid screenshot values to flow', () {
      expect(CalendarModeState.fromRaw('timeline').mode, CalendarMode.flow);
      expect(CalendarModeState.fromRaw('flow').mode, CalendarMode.flow);
      expect(CalendarModeState.fromRaw('unknown').mode, CalendarMode.flow);
      expect(CalendarModeState.fromRaw('').mode, CalendarMode.flow);
    });

    test('supports month and year screenshot values', () {
      expect(CalendarModeState.fromRaw('month').mode, CalendarMode.month);
      expect(CalendarModeState.fromRaw('year').mode, CalendarMode.year);
    });

    test('horizontal indexes and explicit selection share one mode', () {
      final state = CalendarModeState();

      state.setHorizontalIndex(1);
      expect(state.mode, CalendarMode.month);
      expect(state.horizontalIndex, 1);

      state.select(CalendarMode.year);
      expect(state.horizontalIndex, 2);

      state.setHorizontalIndex(99);
      expect(state.mode, CalendarMode.flow);
      expect(state.legacyValue, 'timeline');
    });

    test('a reset before pager creation supplies the current initial page', () {
      final controller = CalendarController(
        modeState: CalendarModeState(initialMode: CalendarMode.year),
      );

      controller.selectMode(CalendarMode.flow);
      final pager = createCalendarPageController(controller);
      addTearDown(pager.dispose);

      expect(pager.initialPage, 0);
    });
  });

  group('CalendarController inline draft', () {
    test('tap empty time creates a 30-minute ephemeral draft', () {
      final controller = CalendarController();
      final start = DateTime(2026, 7, 9, 14, 15);

      controller.tapEmptyTime(start);

      expect(controller.inlineDraft!.startAt, start);
      expect(
        controller.inlineDraft!.endAt,
        start.add(const Duration(minutes: 30)),
      );
      expect(controller.selectedDate, DateTime(2026, 7, 9));
    });

    test('cancel clears the draft', () {
      final controller = CalendarController()
        ..tapEmptyTime(DateTime(2026, 7, 9, 14));

      controller.cancelInlineDraft();

      expect(controller.inlineDraft, isNull);
    });

    test('changing date clears the draft', () {
      final controller = CalendarController()
        ..tapEmptyTime(DateTime(2026, 7, 9, 14));

      controller.changeDate(DateTime(2026, 7, 10));

      expect(controller.selectedDate, DateTime(2026, 7, 10));
      expect(controller.inlineDraft, isNull);
    });

    test('confirm calls mutation once and clears only after success', () async {
      final controller = CalendarController()
        ..tapEmptyTime(DateTime(2026, 7, 9, 14));
      final gate = Completer<void>();
      var calls = 0;

      final confirmation = controller.confirmInlineDraft((draft) async {
        calls++;
        expect(draft, same(controller.inlineDraft));
        await gate.future;
      });

      expect(calls, 1);
      expect(controller.inlineDraft, isNotNull);
      gate.complete();

      expect(await confirmation, isTrue);
      expect(calls, 1);
      expect(controller.inlineDraft, isNull);
    });

    test('failed confirm retains draft for retry', () async {
      final controller = CalendarController()
        ..tapEmptyTime(DateTime(2026, 7, 9, 14));
      var calls = 0;

      final failed = await controller.confirmInlineDraft((_) async {
        calls++;
        throw StateError('network');
      });

      expect(failed, isFalse);
      expect(calls, 1);
      expect(controller.inlineDraft, isNotNull);

      final retried = await controller.confirmInlineDraft((_) async {
        calls++;
      });
      expect(retried, isTrue);
      expect(calls, 2);
      expect(controller.inlineDraft, isNull);
    });

    test('a concurrent confirm does not invoke mutation twice', () async {
      final controller = CalendarController()
        ..tapEmptyTime(DateTime(2026, 7, 9, 14));
      final gate = Completer<void>();
      var calls = 0;

      final first = controller.confirmInlineDraft((_) async {
        calls++;
        await gate.future;
      });
      final second = await controller.confirmInlineDraft((_) async {
        calls++;
      });

      expect(second, isFalse);
      expect(calls, 1);
      gate.complete();
      expect(await first, isTrue);
    });
  });

  group('CalendarController local surfaces', () {
    test('opens Day Detail without changing the selected scale', () {
      final controller = CalendarController(
        modeState: CalendarModeState(initialMode: CalendarMode.month),
      );

      controller.openDay(DateTime(2026, 7, 3, 17));

      expect(controller.mode, CalendarMode.month);
      expect(controller.surface, CalendarSurface.dayDetail);
      expect(controller.selectedDate, DateTime(2026, 7, 3));
    });

    test('Schedule backs into Day Detail and then overview', () {
      final controller = CalendarController()
        ..openDay(DateTime(2026, 7, 3))
        ..openSchedule();

      expect(controller.surface, CalendarSurface.schedule);
      expect(controller.back(), isTrue);
      expect(controller.surface, CalendarSurface.dayDetail);
      expect(controller.back(), isTrue);
      expect(controller.surface, CalendarSurface.overview);
      expect(controller.back(), isFalse);
    });

    test('changing Day Detail date clears an inline Schedule draft', () {
      final controller = CalendarController()
        ..openDay(DateTime(2026, 7, 3))
        ..tapEmptyTime(DateTime(2026, 7, 3, 16));

      controller.openDay(DateTime(2026, 7, 4));

      expect(controller.selectedDate, DateTime(2026, 7, 4));
      expect(controller.inlineDraft, isNull);
      expect(controller.surface, CalendarSurface.dayDetail);
    });
  });
}
