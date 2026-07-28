import 'package:flutter/foundation.dart';

import 'calendar_mode_state.dart';

typedef CalendarDraftMutation =
    Future<void> Function(CalendarInlineDraft draft);

enum CalendarSurface { overview, dayDetail, schedule }

class CalendarInlineDraft {
  final DateTime startAt;
  final DateTime endAt;

  const CalendarInlineDraft({required this.startAt, required this.endAt});

  factory CalendarInlineDraft.at(DateTime startAt) => CalendarInlineDraft(
    startAt: startAt,
    endAt: startAt.add(const Duration(minutes: 30)),
  );
}

/// Pure orchestration state for the Calendar view.
///
/// Network fetching and Flutter controllers stay outside this class. Task 7 can
/// inject the existing create mutation when confirming an inline draft.
class CalendarController {
  final CalendarModeState _modeState;
  DateTime? _selectedDate;
  CalendarInlineDraft? _inlineDraft;
  bool _confirming = false;
  final ValueNotifier<CalendarSurface> surfaceListenable = ValueNotifier(
    CalendarSurface.overview,
  );

  CalendarController({CalendarModeState? modeState, DateTime? selectedDate})
    : _modeState = modeState ?? CalendarModeState(),
      _selectedDate = selectedDate == null ? null : _dayOnly(selectedDate);

  CalendarMode get mode => _modeState.mode;
  int get horizontalIndex => _modeState.horizontalIndex;
  String get legacyModeValue => _modeState.legacyValue;
  DateTime? get selectedDate => _selectedDate;
  CalendarInlineDraft? get inlineDraft => _inlineDraft;
  bool get isConfirmingDraft => _confirming;
  CalendarSurface get surface => surfaceListenable.value;

  bool selectMode(CalendarMode mode) => _modeState.select(mode);

  bool setHorizontalIndex(int index) => _modeState.setHorizontalIndex(index);

  void tapEmptyTime(DateTime startAt) {
    _selectedDate = _dayOnly(startAt);
    _inlineDraft = CalendarInlineDraft.at(startAt);
  }

  void cancelInlineDraft() {
    _inlineDraft = null;
  }

  void changeDate(DateTime date) {
    final next = _dayOnly(date);
    if (_selectedDate == next) return;
    _selectedDate = next;
    _inlineDraft = null;
  }

  void openDay(DateTime date) {
    changeDate(date);
    surfaceListenable.value = CalendarSurface.dayDetail;
  }

  void openSchedule() {
    if (_selectedDate == null) return;
    surfaceListenable.value = CalendarSurface.schedule;
  }

  void backToDay() {
    if (_selectedDate == null) {
      surfaceListenable.value = CalendarSurface.overview;
      return;
    }
    surfaceListenable.value = CalendarSurface.dayDetail;
  }

  void backToOverview() {
    surfaceListenable.value = CalendarSurface.overview;
    _inlineDraft = null;
  }

  bool back() {
    switch (surface) {
      case CalendarSurface.schedule:
        backToDay();
        return true;
      case CalendarSurface.dayDetail:
        backToOverview();
        return true;
      case CalendarSurface.overview:
        return false;
    }
  }

  Future<bool> confirmInlineDraft(CalendarDraftMutation mutation) async {
    final draft = _inlineDraft;
    if (draft == null || _confirming) return false;
    _confirming = true;
    try {
      await mutation(draft);
      if (identical(_inlineDraft, draft)) _inlineDraft = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      _confirming = false;
    }
  }

  void dispose() {
    surfaceListenable.dispose();
  }

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
