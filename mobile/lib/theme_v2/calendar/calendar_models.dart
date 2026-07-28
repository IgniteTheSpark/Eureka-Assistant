import 'dart:collection';

import '../../timeline/timeline.dart';

/// Calendar's interpretation of the backend-owned effective time.
///
/// The Calendar domain deliberately accepts [TimelineItem], not raw timestamps,
/// so there is no path for substituting an asset's capture/created time.
enum CalendarRecordTiming { timed, untimed, allDay }

class CalendarRecord {
  final TimelineItem item;
  final CalendarRecordTiming timing;

  const CalendarRecord._({required this.item, required this.timing});

  factory CalendarRecord.fromTimeline(TimelineItem item) {
    final timing = switch ((item.kind, item.skillName)) {
      ('event', _) when item.allDay => CalendarRecordTiming.allDay,
      ('event', _) => CalendarRecordTiming.timed,
      (_, 'todo') =>
        item.hasScheduledTime
            ? CalendarRecordTiming.timed
            : CalendarRecordTiming.untimed,
      ('input_turn', _) => CalendarRecordTiming.untimed,
      _ =>
        item.hasClockTime
            ? CalendarRecordTiming.timed
            : CalendarRecordTiming.untimed,
    };
    return CalendarRecord._(item: item, timing: timing);
  }

  String get id => item.id;
  DateTime get effectiveAt => item.effectiveAt;
  DateTime? get endAt => item.endAt;
  String get period => item.period;
  bool get isTimed => timing == CalendarRecordTiming.timed;
  bool get isTodo => item.skillName == 'todo';
  bool get isEvent => item.kind == 'event';
}

int compareCalendarItems(TimelineItem a, TimelineItem b) {
  final effective = a.effectiveAt.compareTo(b.effectiveAt);
  if (effective != 0) return effective;
  final id = a.id.compareTo(b.id);
  if (id != 0) return id;
  return a.kind.compareTo(b.kind);
}

DateTime calendarDayOf(DateTime effectiveAt) =>
    DateTime(effectiveAt.year, effectiveAt.month, effectiveAt.day);

/// Deterministic day buckets sourced exclusively from [TimelineItem.effectiveAt].
Map<DateTime, List<TimelineItem>> bucketCalendarItems(
  Iterable<TimelineItem> items,
) {
  final buckets = <DateTime, List<TimelineItem>>{};
  for (final item in items) {
    buckets
        .putIfAbsent(calendarDayOf(item.effectiveAt), () => <TimelineItem>[])
        .add(item);
  }

  final orderedDays = buckets.keys.toList()..sort();
  return UnmodifiableMapView(
    LinkedHashMap.fromEntries([
      for (final day in orderedDays)
        MapEntry(
          day,
          List<TimelineItem>.unmodifiable(
            buckets[day]!..sort(compareCalendarItems),
          ),
        ),
    ]),
  );
}

/// Shared Calendar payload used by the legacy adapter and Theme V2 surfaces.
class CalendarData {
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final Map<DateTime, List<TimelineItem>> byDay;
  final List<CalendarRecord> records;

  factory CalendarData(
    Iterable<TimelineItem> items,
    Map<String, SkillMeta> skills,
  ) {
    final snapshot = List<TimelineItem>.unmodifiable(items);
    return CalendarData._(
      items: snapshot,
      skills: Map<String, SkillMeta>.unmodifiable(skills),
      byDay: bucketCalendarItems(snapshot),
      records: List<CalendarRecord>.unmodifiable(
        snapshot.map(CalendarRecord.fromTimeline),
      ),
    );
  }

  const CalendarData._({
    required this.items,
    required this.skills,
    required this.byDay,
    required this.records,
  });
}

/// A collapsed representation of scheduled todos sharing one visible due
/// minute, matching the legacy grid's minute precision.
///
/// [todos] always retains the individual records so expanding the band never
/// needs to refetch or reconstruct count-only data.
class CalendarTodoBand {
  static const defaultCollapsedDuration = Duration(minutes: 15);

  final DateTime startAt;
  final List<CalendarRecord> todos;
  final Duration collapsedDuration;

  CalendarTodoBand({
    required this.startAt,
    required Iterable<CalendarRecord> todos,
    this.collapsedDuration = defaultCollapsedDuration,
  }) : todos = List<CalendarRecord>.unmodifiable(todos);
}

List<CalendarTodoBand> buildCalendarTodoBands(
  Iterable<CalendarRecord> records,
) {
  final grouped = <DateTime, List<CalendarRecord>>{};
  for (final record in records) {
    if (!record.isTodo || !record.isTimed) continue;
    final at = record.effectiveAt;
    final visibleMinute = DateTime(
      at.year,
      at.month,
      at.day,
      at.hour,
      at.minute,
    );
    grouped.putIfAbsent(visibleMinute, () => <CalendarRecord>[]).add(record);
  }

  final starts = grouped.keys.toList()..sort();
  return List<CalendarTodoBand>.unmodifiable([
    for (final start in starts)
      if (grouped[start]!.length > 1)
        CalendarTodoBand(
          startAt: start,
          todos: grouped[start]!
            ..sort((a, b) => compareCalendarItems(a.item, b.item)),
        ),
  ]);
}
