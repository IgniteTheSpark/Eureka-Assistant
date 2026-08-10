DateTime? parseThemeV2DateTime(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return null;
  return DateTime.tryParse(value.replaceAll('Z', '+00:00'))?.toLocal();
}

String formatSessionDeadline(String raw, {DateTime? now}) {
  final value = parseThemeV2DateTime(raw);
  if (value == null) return raw;
  final reference = (now ?? DateTime.now()).toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final target = DateTime(value.year, value.month, value.day);
  final dayDelta = target.difference(today).inDays;
  final clock = _clock(value);
  if (dayDelta == 0) return '今天 $clock';
  if (dayDelta == 1) return '明天 $clock';
  if (dayDelta > 1 && dayDelta < 7) {
    return '${_weekdays[value.weekday - 1]} $clock';
  }
  if (value.year != today.year) {
    return '${value.year}年${value.month}月${value.day}日 $clock';
  }
  return '${value.month}月${value.day}日 $clock';
}

DateTime defaultTodoDeadline({DateTime? now, DateTime? date}) {
  final reference = (now ?? DateTime.now()).toLocal();
  final cutoff = DateTime(reference.year, reference.month, reference.day, 18);
  if (date != null) {
    final selected = DateTime(date.year, date.month, date.day, 18);
    final selectsToday =
        date.year == reference.year &&
        date.month == reference.month &&
        date.day == reference.day;
    return selectsToday && reference.isAfter(selected)
        ? selected.add(const Duration(days: 1))
        : selected;
  }
  return reference.isAfter(cutoff)
      ? cutoff.add(const Duration(days: 1))
      : cutoff;
}

String themeV2ApiDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}'
      'T${two(value.hour)}:${two(value.minute)}:00+08:00';
}

String formatFullLocalDateTime(Object? raw) {
  final value = parseThemeV2DateTime(raw);
  if (value == null) return raw?.toString() ?? '';
  return '${value.year}年${value.month}月${value.day}日 ${_clock(value)}';
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
