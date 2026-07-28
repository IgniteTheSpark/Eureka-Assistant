import 'calendar_models.dart';

const calendarFallbackDuration = Duration(minutes: 30);

class CalendarTimeLayoutEntry {
  final CalendarRecord record;
  final int startMinute;
  final int endMinute;
  final int columnIndex;
  final int columnCount;

  const CalendarTimeLayoutEntry({
    required this.record,
    required this.startMinute,
    required this.endMinute,
    required this.columnIndex,
    required this.columnCount,
  });

  String get id => record.id;
  Duration get duration => Duration(minutes: endMinute - startMinute);
}

int calendarStartMinute(CalendarRecord record) =>
    record.effectiveAt.hour * 60 + record.effectiveAt.minute;

int calendarEndMinute(CalendarRecord record) {
  final start = calendarStartMinute(record);
  final endAt = record.endAt;
  if (endAt == null || !endAt.isAfter(record.effectiveAt)) {
    return start + calendarFallbackDuration.inMinutes;
  }
  final duration = endAt.difference(record.effectiveAt).inMinutes;
  return start + (duration > 0 ? duration : calendarFallbackDuration.inMinutes);
}

/// Assigns stable Google-Calendar-style columns within overlap clusters.
///
/// Adjacent records do not overlap. A bridging record keeps a transitive
/// cluster together, and every entry exposes the final width denominator.
List<CalendarTimeLayoutEntry> layoutCalendarTime(
  Iterable<CalendarRecord> records,
) {
  final sorted = records.where((record) => record.isTimed).toList()
    ..sort((a, b) {
      final start = calendarStartMinute(a).compareTo(calendarStartMinute(b));
      if (start != 0) return start;
      final end = calendarEndMinute(b).compareTo(calendarEndMinute(a));
      if (end != 0) return end;
      final id = a.id.compareTo(b.id);
      if (id != 0) return id;
      return a.item.kind.compareTo(b.item.kind);
    });

  final result = <CalendarTimeLayoutEntry>[];
  final cluster = <CalendarRecord>[];
  var clusterEnd = -1;

  void flush() {
    if (cluster.isEmpty) return;
    final columnEnds = <int>[];
    final columnOf = <CalendarRecord, int>{};
    for (final record in cluster) {
      final start = calendarStartMinute(record);
      var column = -1;
      for (var i = 0; i < columnEnds.length; i++) {
        if (columnEnds[i] <= start) {
          column = i;
          break;
        }
      }
      if (column == -1) {
        column = columnEnds.length;
        columnEnds.add(0);
      }
      columnEnds[column] = calendarEndMinute(record);
      columnOf[record] = column;
    }

    for (final record in cluster) {
      result.add(
        CalendarTimeLayoutEntry(
          record: record,
          startMinute: calendarStartMinute(record),
          endMinute: calendarEndMinute(record),
          columnIndex: columnOf[record]!,
          columnCount: columnEnds.length,
        ),
      );
    }
    cluster.clear();
    clusterEnd = -1;
  }

  for (final record in sorted) {
    if (cluster.isNotEmpty && calendarStartMinute(record) >= clusterEnd) {
      flush();
    }
    cluster.add(record);
    final end = calendarEndMinute(record);
    if (end > clusterEnd) clusterEnd = end;
  }
  flush();
  return List<CalendarTimeLayoutEntry>.unmodifiable(result);
}
