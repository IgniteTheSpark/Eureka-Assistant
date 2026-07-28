enum CalendarMode { flow, month, year }

class CalendarModeState {
  CalendarMode _mode;

  CalendarModeState({CalendarMode initialMode = CalendarMode.flow})
    : _mode = initialMode;

  factory CalendarModeState.fromRaw(String? raw) =>
      CalendarModeState(initialMode: parse(raw));

  factory CalendarModeState.fromStartDefine() => CalendarModeState.fromRaw(
    const String.fromEnvironment('START_CAL_MODE', defaultValue: 'timeline'),
  );

  static CalendarMode parse(String? raw) => switch (raw) {
    'month' => CalendarMode.month,
    'year' => CalendarMode.year,
    'flow' || 'timeline' => CalendarMode.flow,
    _ => CalendarMode.flow,
  };

  CalendarMode get mode => _mode;
  int get horizontalIndex => _mode.index;
  String get legacyValue => switch (_mode) {
    CalendarMode.flow => 'timeline',
    CalendarMode.month => 'month',
    CalendarMode.year => 'year',
  };

  bool select(CalendarMode mode) {
    if (_mode == mode) return false;
    _mode = mode;
    return true;
  }

  bool setHorizontalIndex(int index) {
    final next = index >= 0 && index < CalendarMode.values.length
        ? CalendarMode.values[index]
        : CalendarMode.flow;
    return select(next);
  }
}
