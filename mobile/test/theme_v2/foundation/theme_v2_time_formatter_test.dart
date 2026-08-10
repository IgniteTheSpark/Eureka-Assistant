import 'package:eureka/theme_v2/foundation/theme_v2_time_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSessionDeadline', () {
    final now = DateTime(2026, 8, 8, 10);

    test('uses readable relative labels before absolute dates', () {
      expect(
        formatSessionDeadline('2026-08-08T18:00:00+08:00', now: now),
        '今天 18:00',
      );
      expect(
        formatSessionDeadline('2026-08-09T11:00:00+08:00', now: now),
        '明天 11:00',
      );
      expect(
        formatSessionDeadline('2026-08-10T17:00:00+08:00', now: now),
        '周一 17:00',
      );
      expect(
        formatSessionDeadline('2026-08-18T12:30:00+08:00', now: now),
        '8月18日 12:30',
      );
      expect(
        formatSessionDeadline('2027-01-02T05:00:00+08:00', now: now),
        '2027年1月2日 05:00',
      );
    });

    test('keeps malformed server values visible for diagnosis', () {
      expect(formatSessionDeadline('not-a-date', now: now), 'not-a-date');
    });
  });

  group('defaultTodoDeadline', () {
    test('uses today through exactly 18:00', () {
      expect(
        defaultTodoDeadline(now: DateTime(2026, 8, 8, 17, 59)),
        DateTime(2026, 8, 8, 18),
      );
      expect(
        defaultTodoDeadline(now: DateTime(2026, 8, 8, 18)),
        DateTime(2026, 8, 8, 18),
      );
    });

    test('uses tomorrow after 18:00', () {
      expect(
        defaultTodoDeadline(now: DateTime(2026, 8, 8, 18, 0, 1)),
        DateTime(2026, 8, 9, 18),
      );
    });

    test('rolls a selected current day forward after 18:00', () {
      expect(
        defaultTodoDeadline(
          now: DateTime(2026, 8, 8, 18, 0, 1),
          date: DateTime(2026, 8, 8),
        ),
        DateTime(2026, 8, 9, 18),
      );
    });

    test('uses a selected date at 18:00 regardless of current time', () {
      expect(
        defaultTodoDeadline(
          now: DateTime(2026, 8, 8, 21),
          date: DateTime(2026, 8, 12),
        ),
        DateTime(2026, 8, 12, 18),
      );
    });
  });
}
