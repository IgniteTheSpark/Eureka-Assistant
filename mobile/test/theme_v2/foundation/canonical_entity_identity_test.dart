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
}
