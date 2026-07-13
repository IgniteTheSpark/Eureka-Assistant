import 'package:eureka/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event timeline JSON uses the canonical calendar card summary', () {
    final item = TimelineItem.fromJson({
      'kind': 'event',
      'id': 'event-1',
      'event_id': 'event-1',
      'effective_at': '2026-07-13T14:00:00',
      'title': '产品评审',
      'subtitle': '会议室',
      'payload': {
        'event_id': 'event-1',
        'title': '产品评审',
        'start_at': '2026-07-13T14:00:00',
        'end_at': '2026-07-13T15:00:00',
        'all_day': false,
        'location': '会议室',
        'description': 'Review',
        'attendees': [
          {'display_name': 'Alex'},
          {'name_raw': 'Bob'},
        ],
      },
    });

    expect(item.payload['description'], 'Review');
    expect(item.subtitle, '14:00–15:00 · 会议室 · Alex +1');
  });
}
