import 'dart:collection';

import '../../timeline/timeline.dart';

/// Calendar's interpretation of the backend-owned effective time.
///
/// The effective date stays backend-owned. Notes are the one presentation
/// exception: when no semantic clock was supplied, their visible clock comes
/// from [TimelineItem.createdAt] instead of being labeled as untimed.
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
      _ when item.period.trim().isNotEmpty => CalendarRecordTiming.untimed,
      (_, 'notes') =>
        item.hasClockTime || _hasNonMidnightTime(item.createdAt)
            ? CalendarRecordTiming.timed
            : CalendarRecordTiming.untimed,
      ('contact', _) =>
        item.hasClockTime || _hasNonMidnightTime(item.effectiveAt)
            ? CalendarRecordTiming.timed
            : CalendarRecordTiming.untimed,
      _ =>
        item.hasClockTime
            ? CalendarRecordTiming.timed
            : CalendarRecordTiming.untimed,
    };
    return CalendarRecord._(item: item, timing: timing);
  }

  String get id => item.id;
  DateTime get effectiveAt => item.effectiveAt;
  DateTime get displayAt => _displayAtFor(item);
  DateTime? get endAt => item.endAt;
  String get period => item.period;
  bool get isTimed => timing == CalendarRecordTiming.timed;
  bool get isTodo => item.skillName == 'todo';
  bool get isEvent => item.kind == 'event';
}

/// A Flow-only projection of one canonical record onto one calendar day.
///
/// Cross-day events can produce multiple slices, but every slice retains the
/// same [record] identity and therefore opens the same detail object.
class CalendarFlowSlice {
  const CalendarFlowSlice({
    required this.record,
    required this.day,
    required this.visibleStart,
    required this.visibleEnd,
    required this.continuesFromPreviousDay,
    required this.continuesIntoNextDay,
  });

  final CalendarRecord record;
  final DateTime day;
  final DateTime visibleStart;
  final DateTime visibleEnd;
  final bool continuesFromPreviousDay;
  final bool continuesIntoNextDay;
}

int compareCalendarItems(TimelineItem a, TimelineItem b) {
  return compareTimelineItems(a, b);
}

bool _hasNonMidnightTime(DateTime value) =>
    value.hour != 0 ||
    value.minute != 0 ||
    value.second != 0 ||
    value.millisecond != 0 ||
    value.microsecond != 0;

DateTime _displayAtFor(TimelineItem item) {
  if (item.skillName != 'notes' ||
      item.hasClockTime ||
      item.period.trim().isNotEmpty) {
    return item.effectiveAt;
  }
  final effective = item.effectiveAt;
  final created = item.createdAt;
  return DateTime(
    effective.year,
    effective.month,
    effective.day,
    created.hour,
    created.minute,
    created.second,
    created.millisecond,
    created.microsecond,
  );
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

/// Project canonical records into immutable half-open day slices for Flow.
Map<DateTime, List<CalendarFlowSlice>> bucketCalendarFlowRecords(
  Iterable<CalendarRecord> records,
) {
  final buckets = <DateTime, List<CalendarFlowSlice>>{};

  void addSlice(CalendarFlowSlice slice) {
    buckets.putIfAbsent(slice.day, () => <CalendarFlowSlice>[]).add(slice);
  }

  for (final record in records) {
    if (record.item.kind == 'input_turn') continue;
    final start = record.effectiveAt;
    final end = record.endAt;
    final startDay = calendarDayOf(start);
    if (!record.isEvent ||
        record.item.allDay ||
        end == null ||
        !end.isAfter(start)) {
      addSlice(
        CalendarFlowSlice(
          record: record,
          day: startDay,
          visibleStart: start,
          visibleEnd: end ?? start,
          continuesFromPreviousDay: false,
          continuesIntoNextDay: false,
        ),
      );
      continue;
    }

    var day = startDay;
    while (day.isBefore(end)) {
      final nextDay = day.add(const Duration(days: 1));
      final visibleStart = start.isAfter(day) ? start : day;
      final visibleEnd = end.isBefore(nextDay) ? end : nextDay;
      if (visibleStart.isBefore(visibleEnd)) {
        addSlice(
          CalendarFlowSlice(
            record: record,
            day: day,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
            continuesFromPreviousDay: start.isBefore(day),
            continuesIntoNextDay: end.isAfter(nextDay),
          ),
        );
      }
      day = nextDay;
    }
  }

  final orderedDays = buckets.keys.toList()..sort();
  return UnmodifiableMapView(
    LinkedHashMap.fromEntries([
      for (final day in orderedDays)
        MapEntry(
          day,
          List<CalendarFlowSlice>.unmodifiable(
            buckets[day]!..sort((a, b) {
              final byStart = a.visibleStart.compareTo(b.visibleStart);
              if (byStart != 0) return byStart;
              return compareCalendarItems(a.record.item, b.record.item);
            }),
          ),
        ),
    ]),
  );
}

class CalendarDayData {
  const CalendarDayData({
    required this.day,
    required this.assets,
    required this.flashes,
  });

  final DateTime day;
  final List<CalendarRecord> assets;
  final List<TimelineItem> flashes;

  int get assetCount => assets.length;
  int get flashCount => flashes.length;
}

/// Shared Calendar payload used by the legacy adapter and Theme V2 surfaces.
class CalendarData {
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final Map<DateTime, List<TimelineItem>> byDay;
  final List<CalendarRecord> records;
  final Map<DateTime, List<CalendarFlowSlice>> flowByDay;

  factory CalendarData(
    Iterable<TimelineItem> items,
    Map<String, SkillMeta> skills,
  ) {
    final snapshot = List<TimelineItem>.unmodifiable(items);
    final records = List<CalendarRecord>.unmodifiable(
      snapshot.map(CalendarRecord.fromTimeline),
    );
    return CalendarData._(
      items: snapshot,
      skills: Map<String, SkillMeta>.unmodifiable(skills),
      byDay: bucketCalendarItems(snapshot),
      records: records,
      flowByDay: bucketCalendarFlowRecords(records),
    );
  }

  const CalendarData._({
    required this.items,
    required this.skills,
    required this.byDay,
    required this.records,
    required this.flowByDay,
  });

  CalendarDayData day(DateTime date) {
    final localDay = calendarDayOf(date);
    final dayItems = byDay[localDay] ?? const <TimelineItem>[];
    return CalendarDayData(
      day: localDay,
      assets: List<CalendarRecord>.unmodifiable(
        dayItems
            .where((item) => item.kind != 'input_turn')
            .map(CalendarRecord.fromTimeline),
      ),
      flashes: List<TimelineItem>.unmodifiable(
        dayItems.where((item) => item.kind == 'input_turn'),
      ),
    );
  }
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
