import 'package:eureka/theme_v2/foundation/canonical_entity_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes built-in aliases to one entity identity', () {
    expect(canonicalEntityKey('calendar'), 'event');
    expect(canonicalEntityKey('note'), 'notes');
    expect(canonicalEntityKey('idea'), 'notes');
    expect(canonicalEntityKey('misc'), 'notes');
  });

  test('pins every built-in icon over stale configured metadata', () {
    expect(resolveEntityIcon('todo', configuredIcon: '✅'), '📋');
    expect(resolveEntityIcon('event', configuredIcon: '⏰'), '📅');
    expect(resolveEntityIcon('contact', configuredIcon: '🪪'), '👤');
    expect(resolveEntityIcon('notes', configuredIcon: '📝'), '✍️');
    expect(resolveEntityIcon('expense', configuredIcon: '🍔'), '💳');
  });

  test('preserves custom skill icons', () {
    expect(resolveEntityIcon('running_training', configuredIcon: '🏃'), '🏃');
    expect(resolveEntityIcon('running_training'), '•');
  });

  test('uses one user-facing label for the event entity', () {
    expect(resolveEntityLabel('event', configuredLabel: '事件'), '日程');
    expect(resolveEntityLabel('calendar'), '日程');
    expect(resolveEntityLabel('todo'), '待办');
    expect(
      resolveEntityLabel('running_training', configuredLabel: '跑步训练'),
      '跑步训练',
    );
    expect(resolveEntityLabel('running_training', fallback: '自定义记录'), '自定义记录');
  });
}
