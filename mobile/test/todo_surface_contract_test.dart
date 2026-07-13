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

  test('todo completion survives legacy cards without a check action', () {
    const spec = RenderSpec(
      cardLayout: 'horizontal',
      icon: 'todo',
      accentColor: 'blue',
      primaryField: 'title',
    );

    for (final payload in [
      {'title': '状态字段', 'status': 'done'},
      {'title': '布尔字段', 'done': true},
      {'title': '兼容字段', 'completed': true},
    ]) {
      final card = buildCard(payload: payload, spec: spec, displayName: 'todo');
      expect(card.checkDone, isTrue, reason: payload.toString());
    }
  });

  test('non-todo records are not made checkable by a done-like field', () {
    const spec = RenderSpec(
      cardLayout: 'horizontal',
      icon: 'notes',
      accentColor: 'amber',
      primaryField: 'title',
    );

    final card = buildCard(
      payload: const {'title': '普通记录', 'status': 'done'},
      spec: spec,
      displayName: 'notes',
    );

    expect(card.checkDone, isNull);
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
