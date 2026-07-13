import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeline keeps the visible year and month pinned above the stream', () {
    final source = File('lib/pages/calendar_page.dart').readAsStringSync();

    expect(source, contains('streamMonthLabel'));
    expect(source, contains('_visibleMonth'));
    expect(source, contains('ValueListenableBuilder<DateTime>'));
    expect(source, contains('_visibleMonth.value = visibleMonth'));
  });

  test('month header owns layout space instead of covering stream rows', () {
    final source = File('lib/pages/calendar_page.dart').readAsStringSync();
    final start = source.indexOf('class _TimelineViewState');
    final end = source.indexOf('Widget _rowWidget', start);
    final timeline = source.substring(start, end);

    expect(timeline, contains('Widget _streamMonthHeader'));
    expect(timeline, contains('return Column('));
    expect(timeline, contains('Expanded(\n          child: Stack('));
    expect(timeline, isNot(contains('padding: const EdgeInsets.only(top: 42')));
  });

  test('sticky date rail resyncs its anchor after programmatic jumps', () {
    final source = File('lib/pages/calendar_page.dart').readAsStringSync();
    final start = source.indexOf('class _DayRowState');
    final end = source.indexOf('class _BandView', start);
    final dayRow = source.substring(start, end);

    expect(dayRow, contains('final anchor = widget.scroll.offset + dy'));
    expect(dayRow, contains('(_pin! - anchor).abs() > 1'));
    expect(dayRow, isNot(contains('_pin ??=')));

    final timelineStart = source.indexOf('class _TimelineViewState');
    final timelineEnd = source.indexOf('Widget _rowWidget', timelineStart);
    final timeline = source.substring(timelineStart, timelineEnd);
    expect(timeline, contains('void _refreshRailsAfterSeek()'));
    expect(timeline, contains('_refreshRailsAfterSeek();'));
  });
}
