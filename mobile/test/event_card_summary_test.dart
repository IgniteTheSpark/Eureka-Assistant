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

    test('prefers a resolved display name over raw and legacy names', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {
              'display_name': 'Alex Chen',
              'name_raw': 'Alex',
              'name': 'Legacy Alex',
            },
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, 'Alex Chen');
    });

    test('falls back to an unresolved raw attendee name', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {'name_raw': 'External Guest'},
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, 'External Guest');
    });

    test('keeps supporting the legacy attendee name', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {'name': 'Legacy Guest'},
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, 'Legacy Guest');
    });

    test('counts duplicate attendee names as separate rows', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {'display_name': 'Alex', 'name_raw': 'Old'},
            {'display_name': 'Alex', 'name_raw': 'Other'},
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, 'Alex +1');
    });

    test('counts unlabeled rows after finding the first visible attendee', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {},
            {'display_name': 'Visible Guest'},
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, 'Visible Guest +1');
    });

    test('falls back from an empty display name to the raw name', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {
              'display_name': ' ',
              'name_raw': 'Raw Guest',
              'name': 'Legacy Guest',
            },
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, 'Raw Guest');
    });

    test('falls back from empty enriched names to the legacy name', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {'display_name': '', 'name_raw': '  ', 'name': 'Legacy Guest'},
          ],
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, 'Legacy Guest');
    });

    test('ignores declared counts at or below the attendee row count', () {
      for (final declaredCount in const [1, 2]) {
        final card = buildCard(
          payload: {
            'attendees': const [
              {'display_name': 'Alex'},
              {'display_name': 'Bob'},
            ],
            'attendees_count': declaredCount,
          },
          spec: synthesizeSpec('event'),
          displayName: 'event',
        );

        expect(card.subtitle, 'Alex +1');
      }
    });

    test(
      'uses a declared count only when it exceeds the attendee row count',
      () {
        final card = buildCard(
          payload: const {
            'attendees': [
              {'display_name': '  ', 'name_raw': '', 'name': ''},
              {'name_raw': 'Visible Guest'},
            ],
            'attendees_count': 4,
          },
          spec: synthesizeSpec('event'),
          displayName: 'event',
        );

        expect(card.subtitle, 'Visible Guest +3');
      },
    );

    test('omits the attendee summary when every row is unlabeled', () {
      final card = buildCard(
        payload: const {
          'attendees': [
            {},
            null,
            {'display_name': ' ', 'name_raw': '', 'name': null},
          ],
          'attendees_count': 5,
        },
        spec: synthesizeSpec('event'),
        displayName: 'event',
      );

      expect(card.subtitle, isEmpty);
    });
  });
}
