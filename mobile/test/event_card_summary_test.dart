import 'package:eureka/render/render_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Event card summary', () {
    test('shows time range before location and attendee summary', () {
      final card = buildCard(
        payload: const {
          'title': '产品评审',
          'start_at': '2026-07-13T14:00:00',
          'end_at': '2026-07-13T15:00:00',
          'location': '会议室',
          'attendees': [
            {'name': 'Alex'},
            {'name': 'Bob'},
            {'name': 'Carol'},
            {'name': 'Dora'},
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, '14:00–15:00 · 会议室 · Alex +3');
      expect(card.metaFields, isEmpty);
    });

    test('omits empty optional fields without changing the time range', () {
      final card = buildCard(
        payload: const {
          'title': '一对一',
          'start_at': '2026-07-13T09:30:00',
          'end_at': '2026-07-13T10:00:00',
          'attendees': [
            {'name': 'Alex'},
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, '09:30–10:00 · Alex');
    });

    test('all-day events do not invent clock times', () {
      final card = buildCard(
        payload: const {
          'title': '公司假日',
          'start_at': '2026-07-13T00:00:00',
          'end_at': '2026-07-14T00:00:00',
          'all_day': true,
          'location': '上海',
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, '全天 · 上海');
    });
  });
}
