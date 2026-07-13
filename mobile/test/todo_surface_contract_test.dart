import 'package:eureka/render/render_spec.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy todo schemas normalize to the three business fields', () {
    const legacy = RenderSpec(
      cardLayout: 'horizontal',
      icon: 'todo',
      accentColor: 'blue',
      primaryField: 'content',
      schemaFields: ['content', 'due_date', 'status', 'period', 'occurred_at'],
      requiredFields: {'content'},
    );

    final normalized = normalizeTodoSpec(legacy);

    expect(normalized.schemaFields, ['title', 'due_date', 'content']);
    expect(normalized.requiredFields, {'title'});
    expect(normalized.primaryField, 'title');
  });

  test('capture fallback time does not imply a scheduled todo', () {
    final item = TimelineItem.fromJson({
      'kind': 'asset',
      'id': 'todo-1',
      'effective_at': '2026-07-10T14:04:38+08:00',
      'created_at': '2026-07-10T14:04:38+08:00',
      'title': '踢足球',
      'subtitle': '',
      'skill_name': 'todo',
      'payload': {'title': '踢足球', 'content': '踢足球'},
      'has_clock_time': false,
      'has_scheduled_time': false,
    });

    expect(item.hasScheduledTime, isFalse);
    expect(item.effectiveAt.hour, 14);
  });
}
